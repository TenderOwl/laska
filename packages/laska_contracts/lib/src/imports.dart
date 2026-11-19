/// The imports of the files of a contract.
///
/// The imports are resolved the way protobuf resolves them: the path of an
/// import is the path of a file of the contract, taken from the directory of
/// the file that imports it, and the types of a file are visible to the files
/// that import it.
library;

import 'model.dart';
import 'types.dart';
import 'well_known.dart';

/// The imports of the files of a contract, resolved.
class ImportGraph {
  /// Creates the graph of the imports of [contract].
  ImportGraph(this.contract);

  /// The contract the imports belong to.
  final Contract contract;

  /// The files of the contract, by their path.
  late final Map<String, ProtoFile> _files = <String, ProtoFile>{
    for (final file in contract.files) normalize(file.path): file,
  };

  /// The file the import [imported] of [file] points to.
  ///
  /// The path of the import is taken from the directory of the file that
  /// imports it, and from the root of the contract when the file is not found
  /// there. The well-known types of protobuf are files of their own, and they
  /// are not part of the contract: their types live in the runtime.
  ProtoFile? resolve(ProtoFile file, ProtoImport imported) {
    final fromDirectory = normalize(
      _join(_directory(file.path), imported.path),
    );
    return _files[fromDirectory] ?? _files[normalize(imported.path)];
  }

  /// The files whose types [file] may use.
  ///
  /// A file sees the types it declares and the types of the files it imports.
  /// A public import passes the types of the imported file to the files that
  /// import the file that imports it.
  Set<ProtoFile> visibleTo(ProtoFile file) {
    final visible = <ProtoFile>{file};
    final queue = <ProtoFile>[];

    for (final imported in file.imports) {
      final target = resolve(file, imported);
      if (target != null && visible.add(target)) {
        queue.add(target);
      }
    }

    while (queue.isNotEmpty) {
      final current = queue.removeLast();
      for (final imported in current.imports) {
        if (!imported.isPublic) {
          continue;
        }
        final target = resolve(current, imported);
        if (target != null && visible.add(target)) {
          queue.add(target);
        }
      }
    }

    return visible;
  }

  /// The file that declares [message].
  ProtoFile? fileOfMessage(Message message) {
    for (final file in contract.files) {
      if (file.messages.contains(message)) {
        return file;
      }
    }
    return null;
  }

  /// The file that declares [enumType].
  ProtoFile? fileOfEnum(EnumType enumType) {
    for (final file in contract.files) {
      if (file.enums.contains(enumType)) {
        return file;
      }
    }
    return null;
  }

  /// The directory of the path [path].
  static String _directory(String path) {
    final index = path.lastIndexOf('/');
    return index < 0 ? '' : path.substring(0, index);
  }

  /// The path [path] joined to the directory [directory].
  static String _join(String directory, String path) =>
      directory.isEmpty ? path : '$directory/$path';

  /// The path [path] without the `.` and the `..` of its parts.
  static String normalize(String path) {
    final parts = <String>[];
    for (final part in path.split('/')) {
      if (part.isEmpty || part == '.') {
        continue;
      }
      if (part == '..') {
        if (parts.isNotEmpty) {
          parts.removeLast();
        }
        continue;
      }
      parts.add(part);
    }
    return parts.join('/');
  }
}

/// Resolves the types the files of the contract refer to.
///
/// A type that is written without a qualifier is looked up in the files the
/// file imports, so the code that is generated refers to the type of the file
/// it comes from. The types that are written with a qualifier keep it: they
/// are resolved from the root of the contract, the way protobuf resolves them.
void resolveImportedTypes(Contract contract, ImportGraph graph) {
  for (final file in contract.files) {
    final visible = graph.visibleTo(file);

    for (final message in file.messages) {
      for (final field in message.allFields) {
        if (field.isMap) {
          field.mapValueType = _resolve(contract, visible, field.mapValueType!);
        } else {
          field.type = _resolve(contract, visible, field.type);
        }
      }
    }

    for (final service in file.services) {
      for (final method in service.methods) {
        method.requestType = _resolve(contract, visible, method.requestType);
        method.responseType = _resolve(contract, visible, method.responseType);
      }
    }
  }
}

/// Resolves the reference [reference] of a file that sees the files [visible].
String _resolve(Contract contract, Set<ProtoFile> visible, String reference) {
  if (scalarTypes.containsKey(reference)) {
    return reference;
  }
  if (wellKnownTypeOf(reference) != null) {
    return reference;
  }
  // A name with a qualifier is resolved from the root of the contract.
  if (reference.contains('.')) {
    return reference;
  }

  for (final file in visible) {
    for (final message in file.messages) {
      if (message.name == reference) {
        return message.fullName;
      }
    }
    for (final enumType in file.enums) {
      if (enumType.name == reference) {
        return enumType.fullName;
      }
    }
  }

  return reference;
}

/// The types the file [file] refers to.
List<String> referencesOf(ProtoFile file) {
  final references = <String>[];

  for (final message in file.messages) {
    for (final field in message.allFields) {
      if (field.isMap) {
        references.add(field.mapValueType!);
      } else {
        references.add(field.type);
      }
    }
  }

  for (final service in file.services) {
    for (final method in service.methods) {
      references.add(method.requestType);
      references.add(method.responseType);
    }
  }

  return references;
}
