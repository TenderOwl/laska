/// The descriptor of a contract.
///
/// The descriptor is the `FileDescriptorSet` of the protocol buffers: the bytes
/// that describe the files of a contract the way the tools of the ecosystem
/// expect them. The reflection service of gRPC serves it, so a tool — `grpcurl`
/// or a client of another language — discovers the methods of a running
/// service without the files of the contract.
///
/// The descriptor holds the structure of a contract: the messages, the fields,
/// the enums, the groups of a `oneof` and the services with their methods. The
/// options of the framework — the HTTP binding of a method, the policy of a
/// call — are read by the framework as the text of the contract, and they are
/// not part of the descriptor: a tool that discovers the schema does not need
/// them.
library;

import 'dart:convert';

import 'imports.dart';
import 'model.dart';
import 'naming.dart';
import 'well_known.dart';

/// The descriptor of the whole contract [contract].
///
/// The descriptor holds every file of the contract and the well-known files the
/// contract uses, so a tool that reads it resolves every type of the contract.
List<int> descriptorOf(Contract contract) =>
    _Builder(contract).build(contract.files);

/// The descriptor of the file [file] and of the files it depends on.
///
/// The files a file depends on are part of the descriptor, because a reader of
/// it resolves the types of the file in the files they are declared in. The
/// well-known files the contract uses are part of it too.
List<int> descriptorOfFile(Contract contract, ProtoFile file) =>
    _Builder(contract).build(<ProtoFile>[file]);

/// The builder of the descriptor of a contract.
class _Builder {
  /// Creates a builder for [contract].
  _Builder(this.contract) : graph = ImportGraph(contract);

  /// The contract the descriptor is built of.
  final Contract contract;

  /// The graph of the imports of the contract.
  final ImportGraph graph;

  /// Builds the descriptor of the files [roots] and of the files they depend
  /// on.
  List<int> build(List<ProtoFile> roots) {
    final files = _collect(roots);

    final writer = _Writer();
    for (final file in files) {
      writer.writeMessage(1, _fileOf(file));
    }
    for (final path in _wellKnownFilesOf(files)) {
      writer.writeMessage(1, _wellKnownFileOf(path));
    }

    return writer.toBytes();
  }

  /// The files [roots] and the files they depend on, the roots first.
  List<ProtoFile> _collect(List<ProtoFile> roots) {
    final files = <ProtoFile>[];
    final seen = <String>{};

    void add(ProtoFile file) {
      if (!seen.add(_pathOf(file))) {
        return;
      }
      files.add(file);
      for (final imported in file.imports) {
        final target = graph.resolve(file, imported);
        if (target != null) {
          add(target);
        }
      }
    }

    for (final root in roots) {
      add(root);
    }

    return files;
  }

  /// The path of the file [file], as it is named in the descriptor.
  String _pathOf(ProtoFile file) => ImportGraph.normalize(file.path);

  /// The descriptor of the file [file].
  List<int> _fileOf(ProtoFile file) {
    final writer = _Writer();

    writer.writeString(1, _pathOf(file));
    if (file.package.isNotEmpty) {
      writer.writeString(2, file.package);
    }

    final dependencies = _dependenciesOf(file);
    for (final dependency in dependencies) {
      writer.writeString(3, dependency.path);
    }
    for (var index = 0; index < dependencies.length; index++) {
      if (dependencies[index].isPublic) {
        writer.writeInt32(10, index);
      }
    }

    final tree = _MessageTree.of(file);
    for (final node in tree.roots) {
      writer.writeMessage(4, _messageOf(node, contract));
    }

    for (final enumType in file.enums) {
      if (enumType.scope.isEmpty) {
        writer.writeMessage(5, _enumOf(enumType));
      }
    }

    for (final service in file.services) {
      writer.writeMessage(6, _serviceOf(service));
    }

    writer.writeString(12, 'proto3');

    return writer.toBytes();
  }

  /// The dependencies of the file [file].
  ///
  /// The imports of the options of the framework — the file of the HTTP
  /// bindings of Google — are not part of the descriptor: they hold the
  /// options, and the framework reads them as the text of the contract.
  List<_Dependency> _dependenciesOf(ProtoFile file) {
    final dependencies = <_Dependency>[];
    final paths = <String>{};

    void add(String path, {bool isPublic = false}) {
      if (!paths.add(path)) {
        return;
      }
      dependencies.add(_Dependency(path, isPublic: isPublic));
    }

    for (final imported in file.imports) {
      final target = graph.resolve(file, imported);
      if (target != null) {
        add(_pathOf(target), isPublic: imported.isPublic);
        continue;
      }

      final wellKnown = wellKnownFileOf(ImportGraph.normalize(imported.path));
      if (wellKnown != null) {
        add(wellKnown.protoPath);
      }
    }

    // A type of a well-known type is used in the file, so the file that
    // declares it is a dependency of it: a reader of the descriptor resolves
    // the type in that file.
    for (final path in _wellKnownFilesOf(<ProtoFile>[file])) {
      add(path);
    }

    return dependencies;
  }

  /// The files of the well-known types the files [files] use.
  List<String> _wellKnownFilesOf(List<ProtoFile> files) {
    final paths = <String>{};

    void collect(String type) {
      final wellKnown = wellKnownTypeOf(type);
      if (wellKnown != null) {
        paths.add(wellKnown.protoPath);
      }
    }

    for (final file in files) {
      for (final message in file.messages) {
        for (final field in message.allFields) {
          if (field.isMap) {
            collect(field.mapValueType!);
          } else {
            collect(field.type);
          }
        }
      }

      for (final service in file.services) {
        for (final method in service.methods) {
          collect(method.requestType);
          collect(method.responseType);
        }
      }
    }

    return paths.toList()..sort();
  }
}

/// The dependency of a file of a contract.
class _Dependency {
  /// Creates a dependency.
  const _Dependency(this.path, {this.isPublic = false});

  /// The path of the file, as it is named in the descriptor.
  final String path;

  /// Whether the import is a public one.
  final bool isPublic;
}

/// A message of a file and the messages declared inside of it.
class _MessageNode {
  /// Creates a node for [message] of [file].
  _MessageNode(this.file, this.message);

  /// The file the message is declared in.
  final ProtoFile file;

  /// The message of the node.
  final Message message;

  /// The package the message belongs to.
  String get package => file.package;

  /// The messages declared inside of the message.
  final List<_MessageNode> children = <_MessageNode>[];

  /// The path of the message inside of its file.
  String get path =>
      message.scope.isEmpty ? message.name : '${message.scope}.${message.name}';

  /// The name of the message, with the package in front of it.
  String get fullName => package.isEmpty ? path : '$package.$path';
}

/// The messages of a file, nested the way they are declared.
class _MessageTree {
  /// Creates the tree of the messages of [file].
  _MessageTree._(this.file) {
    final nodes = <String, _MessageNode>{};
    for (final message in file.messages) {
      nodes[_pathOf(message)] = _MessageNode(file, message);
    }

    for (final message in file.messages) {
      final node = nodes[_pathOf(message)]!;
      final scope = message.scope;
      if (scope.isEmpty) {
        roots.add(node);
        continue;
      }

      final parentPath = scope.contains('.')
          ? scope.substring(0, scope.lastIndexOf('.'))
          : scope;
      final parent = nodes[parentPath];
      if (parent == null) {
        roots.add(node);
      } else {
        parent.children.add(node);
      }
    }
  }

  /// Builds the tree of the messages of [file].
  static _MessageTree of(ProtoFile file) => _MessageTree._(file);

  /// The file the tree belongs to.
  final ProtoFile file;

  /// The messages declared at the top level of the file.
  final List<_MessageNode> roots = <_MessageNode>[];

  /// The path of the message [message] inside of its file.
  static String _pathOf(Message message) =>
      message.scope.isEmpty ? message.name : '${message.scope}.${message.name}';
}

/// The descriptor of the message of the node [node].
List<int> _messageOf(_MessageNode node, Contract contract) {
  final writer = _Writer();
  final message = node.message;

  writer.writeString(1, message.name);

  // The fields of the message: the ones that stand alone, then the members of
  // the groups of a `oneof`. The order of the fields does not matter to a
  // reader of the descriptor: the number of a field is its identity.
  final oneofs = message.oneofs;
  final synthetic = <Field>[];

  for (final field in message.fields) {
    if (field.optional) {
      synthetic.add(field);
      continue;
    }
    writer.writeMessage(2, _fieldOf(field, contract, node));
  }

  for (var index = 0; index < oneofs.length; index++) {
    for (final field in oneofs[index].fields) {
      writer.writeMessage(
        2,
        _fieldOf(field, contract, node, oneofIndex: index),
      );
    }
  }

  // The groups of a `oneof` are declared after the fields that stand alone.
  for (final oneof in oneofs) {
    writer.writeMessage(8, _oneofOf(oneof));
  }

  // A field that tracks its presence gets a group of its own, and the group is
  // synthetic: it exists in the descriptor alone.
  for (var index = 0; index < synthetic.length; index++) {
    writer.writeMessage(
      2,
      _fieldOf(
        synthetic[index],
        contract,
        node,
        oneofIndex: oneofs.length + index,
        proto3Optional: true,
      ),
    );
  }
  for (final field in synthetic) {
    final group = _Writer()..writeString(1, '_${field.name}');
    writer.writeMessage(8, group.toBytes());
  }

  // The messages and the enums declared inside of the message.
  for (final child in node.children) {
    writer.writeMessage(3, _messageOf(child, contract));
  }
  for (final enumType in node.file.enums) {
    if (enumType.scope == node.path) {
      writer.writeMessage(4, _enumOf(enumType));
    }
  }

  // The entry of a map is a message of its own, declared inside of the message
  // that holds the map.
  for (final field in message.allFields) {
    if (field.isMap) {
      writer.writeMessage(3, _mapEntryOf(field, contract, node));
    }
  }

  return writer.toBytes();
}

/// The descriptor of the field [field].
///
/// The [oneofIndex] is the index of the group of a `oneof` the field belongs
/// to, and [proto3Optional] tells that the field tracks its presence.
List<int> _fieldOf(
  Field field,
  Contract contract,
  _MessageNode node, {
  int? oneofIndex,
  bool proto3Optional = false,
}) {
  final writer = _Writer();

  writer.writeString(1, field.name);
  writer.writeInt32(3, field.number);
  // A map is a repeated field of the entries of the map.
  final repeated = field.repeated || field.isMap;
  writer.writeEnum(4, repeated ? _labelRepeated : _labelOptional);

  if (field.isMap) {
    // A map is a repeated message: the entry of the map.
    writer.writeEnum(5, _typeMessage);
    writer.writeString(6, '.${node.fullName}.${_entryNameOf(field)}');
  } else {
    final type = _typeOf(field.type, contract);
    final typeName = type.typeName;
    writer.writeEnum(5, type.descriptorType);
    if (typeName != null) {
      writer.writeString(6, typeName);
    }
  }

  if (oneofIndex != null) {
    writer.writeInt32(9, oneofIndex);
  }

  writer.writeString(10, camelCase(field.name));

  if (proto3Optional) {
    writer.writeBool(17, true);
  }

  return writer.toBytes();
}

/// The name of the entry of the map of the field [field].
String _entryNameOf(Field field) => '${pascalCase(field.name)}Entry';

/// The descriptor of the entry of the map of the field [field].
List<int> _mapEntryOf(Field field, Contract contract, _MessageNode node) {
  final writer = _Writer();

  writer.writeString(1, _entryNameOf(field));

  final key = _Writer()
    ..writeString(1, 'key')
    ..writeInt32(3, 1)
    ..writeEnum(4, _labelOptional);
  final keyType = _typeOf(field.mapKeyType!, contract);
  final keyTypeName = keyType.typeName;
  key.writeEnum(5, keyType.descriptorType);
  if (keyTypeName != null) {
    key.writeString(6, keyTypeName);
  }
  key.writeString(10, 'key');
  writer.writeMessage(2, key.toBytes());

  final value = _Writer()
    ..writeString(1, 'value')
    ..writeInt32(3, 2)
    ..writeEnum(4, _labelOptional);
  final valueType = _typeOf(field.mapValueType!, contract);
  final valueTypeName = valueType.typeName;
  value.writeEnum(5, valueType.descriptorType);
  if (valueTypeName != null) {
    value.writeString(6, valueTypeName);
  }
  value.writeString(10, 'value');
  writer.writeMessage(2, value.toBytes());

  // The entry of a map is a map itself, and the option says so.
  final options = _Writer()..writeBool(7, true);
  writer.writeMessage(7, options.toBytes());

  return writer.toBytes();
}

/// The descriptor of the group of a `oneof`.
List<int> _oneofOf(Oneof oneof) {
  final writer = _Writer()..writeString(1, oneof.name);
  return writer.toBytes();
}

/// The descriptor of the enum [enumType].
List<int> _enumOf(EnumType enumType) {
  final writer = _Writer();

  writer.writeString(1, enumType.name);

  for (final value in enumType.values) {
    final entry = _Writer()
      ..writeString(1, value.name)
      ..writeInt32(2, value.number);
    writer.writeMessage(2, entry.toBytes());
  }

  return writer.toBytes();
}

/// The descriptor of the service [service].
List<int> _serviceOf(Service service) {
  final writer = _Writer();

  writer.writeString(1, service.name);

  for (final method in service.methods) {
    final entry = _Writer()
      ..writeString(1, method.name)
      ..writeString(2, '.${method.requestType}')
      ..writeString(3, '.${method.responseType}');
    writer.writeMessage(2, entry.toBytes());
  }

  return writer.toBytes();
}

/// The type of a field of a contract, in the terms of the descriptor.
class _FieldType {
  /// Creates a type.
  const _FieldType(this.descriptorType, {this.typeName});

  /// The number of the type in the descriptor.
  final int descriptorType;

  /// The name of the type, with the dot in front of it.
  ///
  /// The value is `null` for a scalar type: it has no name.
  final String? typeName;
}

/// The type of the name [name] in the contract [contract].
_FieldType _typeOf(String name, Contract contract) {
  final scalar = _scalarTypes[name];
  if (scalar != null) {
    return _FieldType(scalar);
  }

  if (contract.enumType(name) != null) {
    return _FieldType(_typeEnum, typeName: '.$name');
  }

  return _FieldType(_typeMessage, typeName: '.$name');
}

/// The numbers of the scalar types in the descriptor.
const Map<String, int> _scalarTypes = <String, int>{
  'double': 1,
  'float': 2,
  'int64': 3,
  'uint64': 4,
  'int32': 5,
  'fixed64': 6,
  'fixed32': 7,
  'bool': 8,
  'string': 9,
  'bytes': 12,
  'uint32': 13,
  'sfixed32': 15,
  'sfixed64': 16,
  'sint32': 17,
  'sint64': 18,
};

/// The number of the type of a message.
const int _typeMessage = 11;

/// The number of the type of an enum.
const int _typeEnum = 14;

/// The number of the label of a field that is not repeated.
const int _labelOptional = 1;

/// The number of the label of a repeated field.
const int _labelRepeated = 3;

/// The descriptor of a well-known file of the protocol buffers.
///
/// The well-known types are the same for every contract, and the tools of the
/// ecosystem know them: the descriptor of the file that declares one lets a
/// tool read a field of that type.
List<int> _wellKnownFileOf(String path) {
  final writer = _Writer();

  writer.writeString(1, path);
  writer.writeString(2, 'google.protobuf');

  switch (path) {
    case 'google/protobuf/timestamp.proto':
      writer.writeMessage(4, _secondsAndNanos('Timestamp'));
    case 'google/protobuf/duration.proto':
      writer.writeMessage(4, _secondsAndNanos('Duration'));
    case 'google/protobuf/any.proto':
      writer.writeMessage(4, _anyOf());
    case 'google/protobuf/empty.proto':
      final empty = _Writer()..writeString(1, 'Empty');
      writer.writeMessage(4, empty.toBytes());
  }

  writer.writeString(12, 'proto3');

  return writer.toBytes();
}

/// The descriptor of the message that holds a number of seconds and a number
/// of nanoseconds.
List<int> _secondsAndNanos(String name) {
  final message = _Writer()..writeString(1, name);

  final seconds = _Writer()
    ..writeString(1, 'seconds')
    ..writeInt32(3, 1)
    ..writeEnum(4, _labelOptional)
    ..writeEnum(5, 3)
    ..writeString(10, 'seconds');
  message.writeMessage(2, seconds.toBytes());

  final nanos = _Writer()
    ..writeString(1, 'nanos')
    ..writeInt32(3, 2)
    ..writeEnum(4, _labelOptional)
    ..writeEnum(5, 5)
    ..writeString(10, 'nanos');
  message.writeMessage(2, nanos.toBytes());

  return message.toBytes();
}

/// The descriptor of the message that holds a type and a value.
List<int> _anyOf() {
  final message = _Writer()..writeString(1, 'Any');

  final typeUrl = _Writer()
    ..writeString(1, 'type_url')
    ..writeInt32(3, 1)
    ..writeEnum(4, _labelOptional)
    ..writeEnum(5, 9)
    ..writeString(10, 'typeUrl');
  message.writeMessage(2, typeUrl.toBytes());

  final value = _Writer()
    ..writeString(1, 'value')
    ..writeInt32(3, 2)
    ..writeEnum(4, _labelOptional)
    ..writeEnum(5, 12)
    ..writeString(10, 'value');
  message.writeMessage(2, value.toBytes());

  return message.toBytes();
}

/// Writes the wire format of the protocol buffers.
///
/// The writer is the small part of the format a descriptor needs: the numbers,
/// the strings and the embedded messages.
class _Writer {
  final List<int> _bytes = <int>[];

  /// The bytes that were written.
  List<int> toBytes() => List<int>.unmodifiable(_bytes);

  /// Writes a signed 32 bit integer.
  void writeInt32(int field, int value) {
    _writeTag(field, 0);
    _writeVarint(value);
  }

  /// Writes a boolean.
  void writeBool(int field, bool value) {
    _writeTag(field, 0);
    _writeVarint(value ? 1 : 0);
  }

  /// Writes the number of an enum value.
  void writeEnum(int field, int value) {
    _writeTag(field, 0);
    _writeVarint(value);
  }

  /// Writes a string.
  void writeString(int field, String value) {
    _writeTag(field, 2);
    _writeBytes(utf8.encode(value));
  }

  /// Writes an embedded message.
  void writeMessage(int field, List<int> value) {
    _writeTag(field, 2);
    _writeBytes(value);
  }

  void _writeTag(int field, int wireType) {
    _writeVarint((field << 3) | wireType);
  }

  void _writeVarint(int value) {
    var remaining = value;
    while (remaining < 0 || remaining > 0x7f) {
      _bytes.add((remaining & 0x7f) | 0x80);
      remaining = remaining >>> 7;
    }
    _bytes.add(remaining & 0x7f);
  }

  void _writeBytes(List<int> value) {
    _writeVarint(value.length);
    _bytes.addAll(value);
  }
}
