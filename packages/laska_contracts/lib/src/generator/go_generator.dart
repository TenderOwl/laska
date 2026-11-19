import '../model.dart';
import '../naming.dart';
import '../types.dart';
import '../well_known.dart';
import 'file.dart';
import 'go_runtime.dart';

/// The Go types of the scalar types of a contract.
const Map<String, String> goScalarTypes = <String, String>{
  'string': 'string',
  'bytes': '[]byte',
  'bool': 'bool',
  'int32': 'int32',
  'int64': 'int64',
  'uint32': 'uint32',
  'uint64': 'uint64',
  'sint32': 'int32',
  'sint64': 'int64',
  'fixed32': 'uint32',
  'fixed64': 'uint64',
  'sfixed32': 'int32',
  'sfixed64': 'int64',
  'float': 'float32',
  'double': 'float64',
};

/// The Go types of the keys of a map of a contract.
const Map<String, String> goMapKeyTypes = <String, String>{
  'string': 'string',
  'bool': 'bool',
  'int32': 'int32',
  'int64': 'int64',
  'uint32': 'uint32',
  'uint64': 'uint64',
  'sint32': 'int32',
  'sint64': 'int64',
  'fixed32': 'uint32',
  'fixed64': 'uint64',
  'sfixed32': 'int32',
  'sfixed64': 'int64',
};

/// The words Go keeps for itself, and that a package may not use as a name.
const Set<String> goKeywords = <String>{
  'break',
  'case',
  'chan',
  'const',
  'continue',
  'default',
  'defer',
  'else',
  'fallthrough',
  'for',
  'func',
  'go',
  'goto',
  'if',
  'import',
  'interface',
  'map',
  'package',
  'range',
  'return',
  'select',
  'struct',
  'switch',
  'type',
  'var',
};

/// The version of Go the SDK of a contract is written for.
///
/// The SDK uses the protocols of HTTP/2 of the standard library of Go, and
/// they came with the version 1.24.
const String goLanguageVersion = '1.24';

/// The path of the module of an SDK that has no path of its own.
const String defaultGoModule = 'example.com/laska/sdk';

/// Generates the SDK of a contract in Go.
///
/// The SDK is a module of its own: it holds the messages of the contract, the
/// clients of its services and the runtime they need, so a service written in
/// Go depends on nothing but the standard library of the language.
///
/// The calls of the clients go over gRPC, the way the services of a contract
/// answer on both transports.
class GoGenerator {
  /// Creates a generator for [contract].
  ///
  /// The [module] is the path of the Go module of the SDK, e.g.
  /// `example.com/laska/users`. The name of the package of the module is the
  /// last part of the path, unless [package] names another one.
  GoGenerator(
    this.contract, {
    this.module = defaultGoModule,
    String? package,
  }) : packageName = package ?? packageNameOf(module);

  /// The contract to generate an SDK for.
  final Contract contract;

  /// The path of the Go module of the SDK.
  final String module;

  /// The name of the Go package of the SDK.
  final String packageName;

  late final TypeResolver _types = TypeResolver(contract);

  late final Map<ProtoFile, String> _stems = _computeStems();

  late final Set<String> _usedNames = _reserveNames();

  late final Map<EnumType, Map<EnumValue, String>> _enumValueNames =
      _computeEnumValueNames();

  final Map<Message, Map<Field, String>> _fieldNames =
      <Message, Map<Field, String>>{};

  /// Generates the files of the SDK.
  List<GeneratedFile> generate() {
    final files = <GeneratedFile>[
      GeneratedFile('go.mod', _goMod()),
      GeneratedFile('internal/wire/wire.go', goWireSource),
      GeneratedFile('internal/grpc/grpc.go', goGrpcSource),
      GeneratedFile('wellknown.pb.go', _wellKnown()),
    ];

    if (contract.services.isNotEmpty) {
      files.add(GeneratedFile('client.go', _callOptions()));
    }

    for (final file in contract.files) {
      files.add(GeneratedFile('${_stems[file]}.pb.go', _typesFile(file)));
      if (file.services.isNotEmpty) {
        files.add(
          GeneratedFile('${_stems[file]}_client.pb.go', _clientFile(file)),
        );
      }
    }

    return files;
  }

  /// The name of the Go package of the module [module].
  static String packageNameOf(String module) {
    final last = module.split('/').last;
    var name = last.replaceAll(RegExp(r'[^a-zA-Z0-9_]'), '_').toLowerCase();
    if (name.isEmpty) {
      name = 'sdk';
    }
    if (RegExp(r'^[0-9]').hasMatch(name)) {
      name = '_$name';
    }
    if (goKeywords.contains(name)) {
      name = '${name}_';
    }
    return name;
  }

  String _goMod() => '''
module $module

go $goLanguageVersion
''';

  Map<ProtoFile, String> _computeStems() {
    final used = <String>{};
    final stems = <ProtoFile, String>{};
    for (final file in contract.files) {
      final base = file.path
          .split('/')
          .last
          .replaceFirst(RegExp(r'\.proto$'), '')
          .replaceAll(RegExp(r'[^a-zA-Z0-9_]'), '_');
      var stem = base;
      var index = 2;
      while (used.contains(stem)) {
        stem = '$base$index';
        index++;
      }
      used.add(stem);
      stems[file] = stem;
    }
    return stems;
  }

  /// Reserves the names the types of the contract use.
  ///
  /// The names of a package are one namespace, so a name that is taken is not
  /// used twice: the value of an enum that shares its name with another one is
  /// named after the enum it belongs to.
  Set<String> _reserveNames() {
    final names = <String>{
      for (final type in wellKnownTypes.values) type.dartName,
    };
    for (final message in contract.messages) {
      names.add(message.dartName);
    }
    for (final enumType in contract.enums) {
      names.add(enumType.dartName);
    }
    return names;
  }

  Map<EnumType, Map<EnumValue, String>> _computeEnumValueNames() {
    final names = <EnumType, Map<EnumValue, String>>{};
    for (final enumType in contract.enums) {
      final values = <EnumValue, String>{};
      for (final value in enumType.values) {
        var name = _goConstantName(value.name);
        if (name.isEmpty || RegExp(r'^[0-9]').hasMatch(name)) {
          name = 'Value$name';
        }
        if (_usedNames.contains(name)) {
          name = '${enumType.dartName}$name';
        }
        _usedNames.add(name);
        values[value] = name;
      }
      names[enumType] = values;
    }
    return names;
  }

  /// The Go type of the name [protoType], as it is written in a contract.
  _GoType _baseType(String protoType) {
    final scalar = goScalarTypes[protoType];
    if (scalar != null) {
      return _GoType(
        name: scalar,
        kind: protoType == 'bytes' ? _GoKind.bytes : _GoKind.scalar,
      );
    }

    final wellKnown = _types.findWellKnown(protoType);
    if (wellKnown != null) {
      return _GoType(name: wellKnown.dartName, kind: _GoKind.message);
    }

    final message = _types.findMessage(protoType);
    if (message != null) {
      return _GoType(name: message.dartName, kind: _GoKind.message);
    }

    final enumType = _types.findEnum(protoType);
    if (enumType != null) {
      return _GoType(name: enumType.dartName, kind: _GoKind.enumeration);
    }

    throw StateError('Unknown contract type "$protoType"');
  }

  /// The Go type of the field [field].
  String _goTypeOf(Field field) {
    if (field.isMap) {
      final key = goMapKeyTypes[field.mapKeyType!];
      if (key == null) {
        throw StateError(
          'Unknown type of the key of the map "${field.name}": '
          '"${field.mapKeyType}"',
        );
      }
      final value = _baseType(field.mapValueType!);
      return 'map[$key]${value.isMessage ? '*${value.name}' : value.name}';
    }

    final base = _baseType(field.type);
    if (field.repeated) {
      return '[]${base.isMessage ? '*${base.name}' : base.name}';
    }
    if (base.isMessage) {
      return '*${base.name}';
    }
    if (field.optional || field.oneof != null) {
      return '*${base.name}';
    }
    return base.name;
  }

  /// The names the fields of the message [message] take in Go.
  Map<Field, String> _namesOf(Message message) {
    final names = _fieldNames[message];
    if (names != null) {
      return names;
    }

    final used = <String>{};
    final result = <Field, String>{};
    for (final field in message.allFields) {
      var name = _fieldNameOf(field);
      if (used.contains(name) || _reservedFieldNames.contains(name)) {
        var index = 2;
        while (used.contains('$name$index')) {
          index++;
        }
        name = '$name$index';
      }
      used.add(name);
      result[field] = name;
    }
    _fieldNames[message] = result;
    return result;
  }

  /// The name of the field [field] of the message [message] in Go.
  String _goFieldName(Message message, Field field) =>
      _namesOf(message)[field]!;

  String _fieldNameOf(Field field) {
    final name = pascalCase(field.name);
    if (name.isEmpty || RegExp(r'^[0-9]').hasMatch(name)) {
      return 'Field$name';
    }
    return name;
  }

  /// The names a field may not take, because the message holds them already.
  static const Set<String> _reservedFieldNames = <String>{
    'MarshalProto',
    'UnmarshalProto',
  };

  // The file of the types of a contract.

  String _typesFile(ProtoFile file) {
    final writer = _GoWriter();
    _writeHeader(writer, file.path);
    writer.write('package $packageName');
    writer.blank();

    final imports = <String>[];
    if (file.enums.isNotEmpty) {
      imports.add('"fmt"');
    }
    if (file.messages.isNotEmpty) {
      imports.add('"io"');
    }
    _writeImports(writer, imports, file.messages.isNotEmpty);

    for (final enumType in file.enums) {
      _writeEnum(writer, enumType);
    }

    for (final message in file.messages) {
      _writeMessage(writer, message);
    }

    return writer.text;
  }

  void _writeImports(_GoWriter writer, List<String> imports, bool needsWire) {
    if (imports.isEmpty && !needsWire) {
      return;
    }
    if (imports.length == 1 && !needsWire) {
      writer.write('import ${imports.first}');
      writer.blank();
      return;
    }

    writer.write('import (');
    writer.indent();
    for (final import in imports) {
      writer.write(import);
    }
    if (imports.isNotEmpty && needsWire) {
      writer.blank();
    }
    if (needsWire) {
      writer.write('"$module/internal/wire"');
    }
    writer.dedent();
    writer.write(')');
    writer.blank();
  }

  void _writeEnum(_GoWriter writer, EnumType enumType) {
    final name = enumType.dartName;
    _writeDoc(writer, enumType.comment, name, 'is an enum of the contract.');
    writer.write('type $name int32');
    writer.blank();

    writer.write('const (');
    writer.indent();
    for (final value in enumType.values) {
      final constant = _enumValueNames[enumType]![value]!;
      _writeDoc(
        writer,
        value.comment,
        constant,
        'is the value ${value.name} of the enum.',
      );
      writer.write('$constant $name = ${value.number}');
    }
    writer.dedent();
    writer.write(')');
    writer.blank();

    writer.write('// String returns the name of the value of the enum.');
    writer.write('func (e $name) String() string {');
    writer.indent();
    writer.write('switch e {');
    for (final value in enumType.values) {
      final constant = _enumValueNames[enumType]![value]!;
      writer.write('case $constant:');
      writer.indent();
      writer.write('return "${value.name}"');
      writer.dedent();
    }
    writer.write('default:');
    writer.indent();
    writer.write('return fmt.Sprintf("$name(%d)", int(e))');
    writer.dedent();
    writer.write('}');
    writer.dedent();
    writer.write('}');
    writer.blank();
  }

  void _writeMessage(_GoWriter writer, Message message) {
    final name = message.dartName;
    _writeDoc(writer, message.comment, name, 'is a message of the contract.');
    writer.write('type $name struct {');
    writer.indent();
    for (final field in message.allFields) {
      final fieldName = _goFieldName(message, field);
      _writeDoc(
        writer,
        field.comment,
        fieldName,
        'holds the value of the field "${field.name}".',
      );
      writer.write('$fieldName ${_goTypeOf(field)}');
    }
    writer.dedent();
    writer.write('}');
    writer.blank();

    _writeMarshal(writer, message);
    _writeUnmarshal(writer, message);
    _writeGetters(writer, message);

    for (final field in message.allFields) {
      if (field.isMap) {
        _writeMapEntryReader(writer, message, field);
      }
    }
  }

  void _writeMarshal(_GoWriter writer, Message message) {
    writer.write('// MarshalProto writes the message on the wire.');
    writer.write('func (m *${message.dartName}) MarshalProto() []byte {');
    writer.indent();
    writer.write('w := wire.NewWriter()');

    for (final field in message.fields) {
      _writeMarshalField(writer, message, field);
    }
    for (final group in message.oneofs) {
      _writeMarshalOneof(writer, message, group);
    }

    writer.write('return w.Bytes()');
    writer.dedent();
    writer.write('}');
    writer.blank();
  }

  void _writeMarshalField(_GoWriter writer, Message message, Field field) {
    final fieldName = _goFieldName(message, field);
    final number = field.number;

    if (field.isMap) {
      _writeMarshalMap(writer, message, field);
      return;
    }

    final base = _baseType(field.type);

    if (field.repeated) {
      if (base.isMessage) {
        writer.write('for _, value := range m.$fieldName {');
        writer.indent();
        writer.write('w.WriteMessage($number, value)');
        writer.dedent();
        writer.write('}');
        return;
      }

      if (base.isEnum) {
        writer.write('if len(m.$fieldName) > 0 {');
        writer.indent();
        writer.write('packed := wire.NewWriter()');
        writer.write('for _, value := range m.$fieldName {');
        writer.indent();
        writer.write('packed.WriteRawVarint(uint64(int64(value)))');
        writer.dedent();
        writer.write('}');
        writer.write('w.WriteBytes($number, packed.Bytes())');
        writer.dedent();
        writer.write('}');
        return;
      }

      final encoding = _encodingOf(field.type);
      if (encoding.packable) {
        writer.write('if len(m.$fieldName) > 0 {');
        writer.indent();
        writer.write('packed := wire.NewWriter()');
        writer.write('for _, value := range m.$fieldName {');
        writer.indent();
        writer
            .write('packed.${encoding.rawWriter}(${encoding.write('value')})');
        writer.dedent();
        writer.write('}');
        writer.write('w.WriteBytes($number, packed.Bytes())');
        writer.dedent();
        writer.write('}');
      } else {
        writer.write('for _, value := range m.$fieldName {');
        writer.indent();
        writer
            .write('w.${encoding.writer}($number, ${encoding.write('value')})');
        writer.dedent();
        writer.write('}');
      }
      return;
    }

    if (base.isMessage) {
      writer.write('if m.$fieldName != nil {');
      writer.indent();
      writer.write('w.WriteMessage($number, m.$fieldName)');
      writer.dedent();
      writer.write('}');
      return;
    }

    if (base.isEnum) {
      writer.write('if m.$fieldName != 0 {');
      writer.indent();
      writer.write('w.WriteEnum($number, int32(m.$fieldName))');
      writer.dedent();
      writer.write('}');
      return;
    }

    final encoding = _encodingOf(field.type);
    if (_isPointerScalar(field)) {
      writer.write('if m.$fieldName != nil {');
      writer.indent();
      writer.write(
        'w.${encoding.writer}($number, ${encoding.write('*m.$fieldName')})',
      );
      writer.dedent();
      writer.write('}');
      return;
    }

    writer.write('if ${_notEmpty(field, fieldName)} {');
    writer.indent();
    writer.write(
      'w.${encoding.writer}($number, ${encoding.write('m.$fieldName')})',
    );
    writer.dedent();
    writer.write('}');
  }

  void _writeMarshalOneof(_GoWriter writer, Message message, Oneof group) {
    for (var i = 0; i < group.fields.length; i++) {
      final field = group.fields[i];
      final fieldName = _goFieldName(message, field);
      final base = _baseType(field.type);
      writer.write('${i == 0 ? 'if' : '} else if'} m.$fieldName != nil {');
      writer.indent();
      if (base.isMessage) {
        writer.write('w.WriteMessage(${field.number}, m.$fieldName)');
      } else if (base.isEnum) {
        writer.write('w.WriteEnum(${field.number}, int32(*m.$fieldName))');
      } else {
        final encoding = _encodingOf(field.type);
        writer.write(
          'w.${encoding.writer}(${field.number}, '
          '${encoding.write('*m.$fieldName')})',
        );
      }
      writer.dedent();
    }
    if (group.fields.isNotEmpty) {
      writer.write('}');
    }
  }

  void _writeMarshalMap(_GoWriter writer, Message message, Field field) {
    final fieldName = _goFieldName(message, field);
    final keyEncoding = _encodingOf(field.mapKeyType!);
    final valueBase = _baseType(field.mapValueType!);

    writer.write('for key, value := range m.$fieldName {');
    writer.indent();
    writer.write('entry := wire.NewWriter()');
    writer.write('entry.${keyEncoding.writer}(1, key)');
    if (valueBase.isMessage) {
      writer.write('if value != nil {');
      writer.indent();
      writer.write('entry.WriteMessage(2, value)');
      writer.dedent();
      writer.write('}');
    } else if (valueBase.isEnum) {
      writer.write('entry.WriteEnum(2, int32(value))');
    } else {
      final valueEncoding = _encodingOf(field.mapValueType!);
      writer.write(
          'entry.${valueEncoding.writer}(2, ${valueEncoding.write('value')})');
    }
    writer.write('w.WriteBytes(${field.number}, entry.Bytes())');
    writer.dedent();
    writer.write('}');
  }

  void _writeUnmarshal(_GoWriter writer, Message message) {
    writer.write('// UnmarshalProto reads the message out of its bytes.');
    writer.write(
      'func (m *${message.dartName}) UnmarshalProto(data []byte) error {',
    );
    writer.indent();
    writer.write('*m = ${message.dartName}{}');
    writer.write('r := wire.NewReader(data)');
    writer.write('for {');
    writer.indent();
    writer.write('field, typ, err := r.Next()');
    writer.write('if err == io.EOF {');
    writer.indent();
    writer.write('break');
    writer.dedent();
    writer.write('}');
    writer.write('if err != nil {');
    writer.indent();
    writer.write('return err');
    writer.dedent();
    writer.write('}');
    writer.write('switch field {');
    for (final field in message.allFields) {
      _writeUnmarshalField(writer, message, field);
    }
    writer.write('default:');
    writer.indent();
    writer.write('if err := r.Skip(typ); err != nil {');
    writer.indent();
    writer.write('return err');
    writer.dedent();
    writer.write('}');
    writer.dedent();
    writer.write('}');
    writer.dedent();
    writer.write('}');
    writer.write('return nil');
    writer.dedent();
    writer.write('}');
    writer.blank();
  }

  void _writeUnmarshalField(_GoWriter writer, Message message, Field field) {
    final fieldName = _goFieldName(message, field);
    final number = field.number;

    writer.write('case $number:');
    writer.indent();

    if (field.isMap) {
      _writeUnmarshalMap(writer, message, field);
      writer.dedent();
      return;
    }

    final base = _baseType(field.type);

    if (field.repeated && base.isMessage) {
      _writeSkipUnless(writer, 'wire.TypeBytes');
      writer.write('data, err := r.ReadBytes()');
      _writeReturnOnError(writer);
      writer.write('item := &${base.name}{}');
      writer.write('if err := item.UnmarshalProto(data); err != nil {');
      writer.indent();
      writer.write('return err');
      writer.dedent();
      writer.write('}');
      writer.write('m.$fieldName = append(m.$fieldName, item)');
      writer.dedent();
      return;
    }

    if (field.repeated) {
      if (base.isEnum) {
        writer.write('if typ == wire.TypeBytes {');
        writer.indent();
        writer.write('packed, err := r.ReadBytes()');
        _writeReturnOnError(writer);
        writer.write('values, err := wire.UnpackInt32(packed)');
        _writeReturnOnError(writer);
        writer.write('for _, value := range values {');
        writer.indent();
        writer
            .write('m.$fieldName = append(m.$fieldName, ${base.name}(value))');
        writer.dedent();
        writer.write('}');
        writer.write('continue');
        writer.dedent();
        writer.write('}');
        _writeSkipUnless(writer, 'wire.TypeVarint');
        writer.write('number, err := r.ReadEnum()');
        _writeReturnOnError(writer);
        writer
            .write('m.$fieldName = append(m.$fieldName, ${base.name}(number))');
        writer.dedent();
        return;
      }

      final encoding = _encodingOf(field.type);
      if (encoding.packable) {
        writer.write('if typ == wire.TypeBytes {');
        writer.indent();
        writer.write('packed, err := r.ReadBytes()');
        _writeReturnOnError(writer);
        writer.write('values, err := wire.${encoding.unpack}(packed)');
        _writeReturnOnError(writer);
        writer.write('m.$fieldName = append(m.$fieldName, values...)');
        writer.write('continue');
        writer.dedent();
        writer.write('}');
      }
      _writeSkipUnless(writer, encoding.wireType);
      writer.write('value, err := r.${encoding.reader}()');
      _writeReturnOnError(writer);
      writer.write('m.$fieldName = append(m.$fieldName, value)');
      writer.dedent();
      return;
    }

    if (base.isMessage) {
      _writeSkipUnless(writer, 'wire.TypeBytes');
      writer.write('data, err := r.ReadBytes()');
      _writeReturnOnError(writer);
      writer.write('item := &${base.name}{}');
      writer.write('if err := item.UnmarshalProto(data); err != nil {');
      writer.indent();
      writer.write('return err');
      writer.dedent();
      writer.write('}');
      writer.write('m.$fieldName = item');
      writer.dedent();
      return;
    }

    if (base.isEnum) {
      _writeSkipUnless(writer, 'wire.TypeVarint');
      writer.write('number, err := r.ReadEnum()');
      _writeReturnOnError(writer);
      if (_isPointerScalar(field)) {
        writer.write('value := ${base.name}(number)');
        writer.write('m.$fieldName = &value');
      } else {
        writer.write('m.$fieldName = ${base.name}(number)');
      }
      _writeClearOneof(writer, message, field);
      writer.dedent();
      return;
    }

    final encoding = _encodingOf(field.type);
    _writeSkipUnless(writer, encoding.wireType);
    writer.write('value, err := r.${encoding.reader}()');
    _writeReturnOnError(writer);
    if (_isPointerScalar(field)) {
      writer.write('m.$fieldName = &value');
    } else {
      writer.write('m.$fieldName = ${encoding.read('value')}');
    }
    _writeClearOneof(writer, message, field);
    writer.dedent();
  }

  /// Writes the code that empties the other members of the group of a field.
  void _writeClearOneof(_GoWriter writer, Message message, Field field) {
    final groupName = field.oneof;
    if (groupName == null) {
      return;
    }
    for (final group in message.oneofs) {
      if (group.name != groupName) {
        continue;
      }
      for (final member in group.fields) {
        if (identical(member, field)) {
          continue;
        }
        writer.write('m.${_goFieldName(message, member)} = nil');
      }
    }
  }

  void _writeUnmarshalMap(_GoWriter writer, Message message, Field field) {
    final fieldName = _goFieldName(message, field);
    final helper = _mapEntryName(message, field);

    _writeSkipUnless(writer, 'wire.TypeBytes');
    writer.write('entry, err := r.ReadBytes()');
    _writeReturnOnError(writer);
    writer.write('key, value, err := $helper(entry)');
    _writeReturnOnError(writer);
    writer.write('if m.$fieldName == nil {');
    writer.indent();
    writer.write('m.$fieldName = ${_goTypeOf(field)}{}');
    writer.dedent();
    writer.write('}');
    writer.write('m.$fieldName[key] = value');
  }

  /// Writes the function that reads the entry of the map of a field.
  void _writeMapEntryReader(_GoWriter writer, Message message, Field field) {
    final helper = _mapEntryName(message, field);
    final keyBase = _baseType(field.mapKeyType!);
    final valueBase = _baseType(field.mapValueType!);
    final keyEncoding = _encodingOf(field.mapKeyType!);
    final valueEncoding = _encodingOf(field.mapValueType!);

    writer.write(
      '// $helper reads the entry of the map of the field '
      '"${field.name}" of the message.',
    );
    writer.write(
      'func $helper(data []byte) (${keyBase.name}, '
      '${valueBase.isMessage ? '*${valueBase.name}' : valueBase.name}, error) {',
    );
    writer.indent();
    writer.write('r := wire.NewReader(data)');
    writer.write('var key ${keyBase.name}');
    if (valueBase.isMessage) {
      writer.write('var value *${valueBase.name}');
    } else {
      writer.write('var value ${valueBase.name}');
    }
    writer.write('for {');
    writer.indent();
    writer.write('field, typ, err := r.Next()');
    writer.write('if err == io.EOF {');
    writer.indent();
    writer.write('break');
    writer.dedent();
    writer.write('}');
    writer.write('if err != nil {');
    writer.indent();
    writer.write('return key, value, err');
    writer.dedent();
    writer.write('}');
    writer.write('switch field {');
    writer.write('case 1:');
    writer.indent();
    _writeSkipUnless(writer, keyEncoding.wireType,
        errorReturn: 'key, value, err');
    writer.write('text, err := r.${keyEncoding.reader}()');
    writer.write('if err != nil {');
    writer.indent();
    writer.write('return key, value, err');
    writer.dedent();
    writer.write('}');
    writer.write('key = ${keyEncoding.read('text')}');
    writer.dedent();
    writer.write('case 2:');
    writer.indent();
    if (valueBase.isMessage) {
      _writeSkipUnless(writer, 'wire.TypeBytes',
          errorReturn: 'key, value, err');
      writer.write('data, err := r.ReadBytes()');
      writer.write('if err != nil {');
      writer.indent();
      writer.write('return key, value, err');
      writer.dedent();
      writer.write('}');
      writer.write('item := &${valueBase.name}{}');
      writer.write('if err := item.UnmarshalProto(data); err != nil {');
      writer.indent();
      writer.write('return key, value, err');
      writer.dedent();
      writer.write('}');
      writer.write('value = item');
    } else if (valueBase.isEnum) {
      _writeSkipUnless(writer, 'wire.TypeVarint',
          errorReturn: 'key, value, err');
      writer.write('number, err := r.ReadEnum()');
      writer.write('if err != nil {');
      writer.indent();
      writer.write('return key, value, err');
      writer.dedent();
      writer.write('}');
      writer.write('value = ${valueBase.name}(number)');
    } else {
      _writeSkipUnless(
        writer,
        valueEncoding.wireType,
        errorReturn: 'key, value, err',
      );
      writer.write('text, err := r.${valueEncoding.reader}()');
      writer.write('if err != nil {');
      writer.indent();
      writer.write('return key, value, err');
      writer.dedent();
      writer.write('}');
      writer.write('value = ${valueEncoding.read('text')}');
    }
    writer.dedent();
    writer.write('default:');
    writer.indent();
    writer.write('if err := r.Skip(typ); err != nil {');
    writer.indent();
    writer.write('return key, value, err');
    writer.dedent();
    writer.write('}');
    writer.dedent();
    writer.write('}');
    writer.dedent();
    writer.write('}');
    writer.write('return key, value, nil');
    writer.dedent();
    writer.write('}');
    writer.blank();
  }

  void _writeGetters(_GoWriter writer, Message message) {
    for (final field in message.allFields) {
      final fieldName = _goFieldName(message, field);
      final base = field.isMap ? null : _baseType(field.type);
      final pointer = !field.isMap && _isPointerScalar(field);
      final type = pointer ? base!.name : _goTypeOf(field);

      writer.write('// Get$fieldName returns the value of the field.');
      writer.write('func (m *${message.dartName}) Get$fieldName() $type {');
      writer.indent();
      if (field.repeated || field.isMap) {
        writer.write('if m == nil {');
        writer.indent();
        writer.write('return nil');
        writer.dedent();
        writer.write('}');
        writer.write('return m.$fieldName');
      } else if (pointer) {
        writer.write('if m == nil || m.$fieldName == nil {');
        writer.indent();
        writer.write('return ${_zeroOf(base!)}');
        writer.dedent();
        writer.write('}');
        writer.write('return *m.$fieldName');
      } else if (base!.isMessage) {
        writer.write('if m == nil {');
        writer.indent();
        writer.write('return nil');
        writer.dedent();
        writer.write('}');
        writer.write('return m.$fieldName');
      } else {
        writer.write('if m == nil {');
        writer.indent();
        writer.write('return ${_zeroOf(base)}');
        writer.dedent();
        writer.write('}');
        writer.write('return m.$fieldName');
      }
      writer.dedent();
      writer.write('}');
      writer.blank();
    }
  }

  // The file of the clients of the services of a contract.

  String _clientFile(ProtoFile file) {
    final writer = _GoWriter();
    _writeHeader(writer, file.path);
    writer.write('package $packageName');
    writer.blank();

    final needsWire = file.services.any(
      (service) =>
          service.methods.any((method) => _responseBase(method).isEnum),
    );

    writer.write('import (');
    writer.indent();
    writer.write('"context"');
    writer.blank();
    writer.write('"$module/internal/grpc"');
    if (needsWire) {
      writer.blank();
      writer.write('"$module/internal/wire"');
    }
    writer.dedent();
    writer.write(')');
    writer.blank();

    for (final service in file.services) {
      _writeServiceClient(writer, service);
    }

    return writer.text;
  }

  void _writeServiceClient(_GoWriter writer, Service service) {
    final name = pascalCase(service.name);

    writer.write(
      '// ${name}Client is the client of the `${service.fullName}` service.',
    );
    writer.write('type ${name}Client struct {');
    writer.indent();
    writer.write('// conn is the connection to the server.');
    writer.write('conn *grpc.Conn');
    writer.write('// options are the options of the calls of the client.');
    writer.write('options CallOptions');
    writer.dedent();
    writer.write('}');
    writer.blank();

    writer.write(
      '// New${name}Client opens a connection to the service at [target].',
    );
    writer.write('//');
    writer.write('// The target is a host and a port, e.g. `localhost:50051`.');
    writer.write(
      'func New${name}Client(target string, opts ...CallOptions) '
      '(*${name}Client, error) {',
    );
    writer.indent();
    writer.write('options := CallOptions{}');
    writer.write('if len(opts) > 0 {');
    writer.indent();
    writer.write('options = opts[0]');
    writer.dedent();
    writer.write('}');
    writer.write('conn, err := grpc.Dial(target, options.Timeout)');
    writer.write('if err != nil {');
    writer.indent();
    writer.write('return nil, err');
    writer.dedent();
    writer.write('}');
    writer.write('return &${name}Client{conn: conn, options: options}, nil');
    writer.dedent();
    writer.write('}');
    writer.blank();

    writer.write('// Close closes the connection of the client.');
    writer.write('func (c *${name}Client) Close() error {');
    writer.indent();
    writer.write('return c.conn.Close()');
    writer.dedent();
    writer.write('}');
    writer.blank();

    for (final method in service.methods) {
      _writeClientMethod(writer, service, method);
    }
  }

  void _writeClientMethod(_GoWriter writer, Service service, Method method) {
    final name = pascalCase(service.name);
    final methodName = _clientMethodName(service, method);
    final request = _baseType(method.requestType);
    final response = _responseBase(method);
    final responseType =
        response.isMessage ? '*${response.name}' : response.name;

    writer.write(
      '// $methodName calls the `${method.name}` method of the service.',
    );
    writer.write(
      'func (c *${name}Client) $methodName('
      'ctx context.Context, request *${request.name}, opts ...CallOptions) '
      '($responseType, error) {',
    );
    writer.indent();
    writer.write('options := c.options');
    writer.write('if len(opts) > 0 {');
    writer.indent();
    writer.write('options = opts[0]');
    writer.dedent();
    writer.write('}');
    writer.write('if options.Timeout > 0 {');
    writer.indent();
    writer.write('var cancel context.CancelFunc');
    writer.write('ctx, cancel = context.WithTimeout(ctx, options.Timeout)');
    writer.write('defer cancel()');
    writer.dedent();
    writer.write('}');
    writer.write(
      'raw, err := c.conn.Invoke(ctx, '
      '"/${service.fullName}/${method.name}", '
      'request.MarshalProto(), options.Metadata)',
    );
    writer.write('if err != nil {');
    writer.indent();
    writer.write('return nil, err');
    writer.dedent();
    writer.write('}');

    if (response.isEnum) {
      writer.write('number, err := wire.ReadRawVarint(raw)');
      writer.write('if err != nil {');
      writer.indent();
      writer.write('return nil, err');
      writer.dedent();
      writer.write('}');
      writer.write('return ${response.name}(int32(number)), nil');
    } else {
      writer.write('response := &${response.name}{}');
      writer.write('if err := response.UnmarshalProto(raw); err != nil {');
      writer.indent();
      writer.write('return nil, err');
      writer.dedent();
      writer.write('}');
      writer.write('return response, nil');
    }

    writer.dedent();
    writer.write('}');
    writer.blank();
  }

  /// The type of the answer of the method [method].
  _GoType _responseBase(Method method) {
    final response = _types.findMessage(method.responseType);
    if (response != null) {
      return _GoType(name: response.dartName, kind: _GoKind.message);
    }
    final wellKnown = _types.findWellKnown(method.responseType);
    if (wellKnown != null) {
      return _GoType(name: wellKnown.dartName, kind: _GoKind.message);
    }
    final enumType = _types.findEnum(method.responseType);
    if (enumType != null) {
      return _GoType(name: enumType.dartName, kind: _GoKind.enumeration);
    }
    throw StateError('Unknown contract type "${method.responseType}"');
  }

  // The files every SDK holds.

  String _callOptions() {
    final writer = _GoWriter();
    _writeHeader(writer, null);
    writer.write('package $packageName');
    writer.blank();
    writer.write('import "time"');
    writer.blank();
    writer.write('// CallOptions holds the options of a call to a service.');
    writer.write('type CallOptions struct {');
    writer.indent();
    writer.write(
      '// Timeout of the call. The timeout of the client is used when it is '
      'zero.',
    );
    writer.write('Timeout time.Duration');
    writer.write('// Metadata is sent with the call.');
    writer.write('Metadata map[string]string');
    writer.dedent();
    writer.write('}');
    writer.blank();
    return writer.text;
  }

  String _wellKnown() {
    final writer = _GoWriter();
    _writeHeader(writer, null);
    writer.write('package $packageName');
    writer.blank();
    writer.write('import (');
    writer.indent();
    writer.write('"io"');
    writer.blank();
    writer.write('"$module/internal/wire"');
    writer.dedent();
    writer.write(')');
    writer.blank();

    _writeWellKnownMessage(
      writer,
      'ProtoTimestamp',
      'is the time of the protocol buffers.',
      <_WellKnownField>[
        _WellKnownField(
          'Seconds',
          1,
          'int64',
          'is the number of the seconds.',
          protoType: 'int64',
        ),
        _WellKnownField(
          'Nanos',
          2,
          'int32',
          'is the number of the nanoseconds.',
          protoType: 'int32',
        ),
      ],
    );
    _writeWellKnownMessage(
      writer,
      'ProtoDuration',
      'is the duration of the protocol buffers.',
      <_WellKnownField>[
        _WellKnownField(
          'Seconds',
          1,
          'int64',
          'is the number of the seconds.',
          protoType: 'int64',
        ),
        _WellKnownField(
          'Nanos',
          2,
          'int32',
          'is the number of the nanoseconds.',
          protoType: 'int32',
        ),
      ],
    );
    _writeWellKnownMessage(
      writer,
      'ProtoAny',
      'is a message of an unknown type of the protocol buffers.',
      <_WellKnownField>[
        _WellKnownField(
          'TypeUrl',
          1,
          'string',
          'is the address of the type.',
        ),
        _WellKnownField(
          'Value',
          2,
          '[]byte',
          'holds the bytes of the message.',
          protoType: 'bytes',
        ),
      ],
    );
    _writeWellKnownMessage(
      writer,
      'ProtoEmpty',
      'is the empty message of the protocol buffers.',
      const <_WellKnownField>[],
    );

    return writer.text;
  }

  void _writeWellKnownMessage(
    _GoWriter writer,
    String name,
    String doc,
    List<_WellKnownField> fields,
  ) {
    writer.write('// $name $doc');
    writer.write('type $name struct {');
    writer.indent();
    for (final field in fields) {
      writer.write('// ${field.name} ${field.doc}');
      writer.write('${field.name} ${field.type}');
    }
    writer.dedent();
    writer.write('}');
    writer.blank();

    writer.write('// MarshalProto writes the message on the wire.');
    writer.write('func (m *$name) MarshalProto() []byte {');
    writer.indent();
    writer.write('w := wire.NewWriter()');
    for (final field in fields) {
      final encoding = _encodingOf(field.protoType);
      writer.write('if ${_notEmptyType(field.type, 'm.${field.name}')} {');
      writer.indent();
      writer.write(
        'w.${encoding.writer}(${field.number}, '
        '${encoding.write('m.${field.name}')})',
      );
      writer.dedent();
      writer.write('}');
    }
    writer.write('return w.Bytes()');
    writer.dedent();
    writer.write('}');
    writer.blank();

    writer.write('// UnmarshalProto reads the message out of its bytes.');
    writer.write('func (m *$name) UnmarshalProto(data []byte) error {');
    writer.indent();
    writer.write('*m = $name{}');
    writer.write('r := wire.NewReader(data)');
    writer.write('for {');
    writer.indent();
    writer.write('field, typ, err := r.Next()');
    writer.write('if err == io.EOF {');
    writer.indent();
    writer.write('break');
    writer.dedent();
    writer.write('}');
    writer.write('if err != nil {');
    writer.indent();
    writer.write('return err');
    writer.dedent();
    writer.write('}');
    writer.write('switch field {');
    for (final field in fields) {
      final encoding = _encodingOf(field.protoType);
      writer.write('case ${field.number}:');
      writer.indent();
      _writeSkipUnless(writer, encoding.wireType);
      writer.write('value, err := r.${encoding.reader}()');
      _writeReturnOnError(writer);
      writer.write('m.${field.name} = ${encoding.read('value')}');
      writer.dedent();
    }
    writer.write('default:');
    writer.indent();
    writer.write('if err := r.Skip(typ); err != nil {');
    writer.indent();
    writer.write('return err');
    writer.dedent();
    writer.write('}');
    writer.dedent();
    writer.write('}');
    writer.dedent();
    writer.write('}');
    writer.write('return nil');
    writer.dedent();
    writer.write('}');
    writer.blank();
  }

  // The helpers of the generated code.

  void _writeHeader(_GoWriter writer, String? source) {
    writer.write('// GENERATED CODE - DO NOT MODIFY BY HAND.');
    writer.write('//');
    if (source != null) {
      writer.write('// Source: $source');
    }
    writer.write('// Regenerate with: laska contract sdk --lang=go');
    writer.blank();
  }

  void _writeDoc(
      _GoWriter writer, String? comment, String name, String fallback) {
    final text = comment == null || comment.trim().isEmpty
        ? '$name $fallback'
        : '$name is ${_withArticle(_lowerFirst(comment.trim()))}';
    final lines = text.split('\n');
    writer.write('// ${lines.first.trim()}');
    for (final line in lines.skip(1)) {
      writer.write('// ${line.trim()}');
    }
  }

  void _writeSkipUnless(
    _GoWriter writer,
    String wireType, {
    String errorReturn = 'err',
  }) {
    writer.write('if typ != $wireType {');
    writer.indent();
    writer.write('if err := r.Skip(typ); err != nil {');
    writer.indent();
    writer.write('return $errorReturn');
    writer.dedent();
    writer.write('}');
    writer.write('continue');
    writer.dedent();
    writer.write('}');
  }

  void _writeReturnOnError(_GoWriter writer) {
    writer.write('if err != nil {');
    writer.indent();
    writer.write('return err');
    writer.dedent();
    writer.write('}');
  }

  /// The condition that tells the field [field] holds a value.
  String _notEmpty(Field field, String fieldName) {
    switch (field.type) {
      case 'string':
        return 'm.$fieldName != ""';
      case 'bytes':
        return 'len(m.$fieldName) > 0';
      case 'bool':
        return 'm.$fieldName';
      default:
        return 'm.$fieldName != 0';
    }
  }

  /// The condition that tells the value [expression] holds something.
  String _notEmptyType(String type, String expression) {
    switch (type) {
      case 'string':
        return '$expression != ""';
      case '[]byte':
        return 'len($expression) > 0';
      case 'bool':
        return expression;
      default:
        return '$expression != 0';
    }
  }

  /// The value of the Go type [type] that holds nothing.
  String _zeroOf(_GoType type) {
    switch (type.kind) {
      case _GoKind.message:
      case _GoKind.bytes:
        return 'nil';
      case _GoKind.enumeration:
        return '${type.name}(0)';
      case _GoKind.scalar:
        switch (type.name) {
          case 'string':
            return '""';
          case 'bool':
            return 'false';
          default:
            return '0';
        }
    }
  }

  /// Whether the field [field] holds its value behind a pointer.
  bool _isPointerScalar(Field field) {
    if (field.repeated || field.isMap) {
      return false;
    }
    if (!field.optional && field.oneof == null) {
      return false;
    }
    return !_baseType(field.type).isMessage;
  }

  /// The name of the method of the client of the service [service].
  String _clientMethodName(Service service, Method method) {
    final used = <String>{'Close'};
    for (final other in service.methods) {
      if (identical(other, method)) {
        break;
      }
      used.add(_clientMethodNameOf(other));
    }

    var name = _clientMethodNameOf(method);
    if (used.contains(name)) {
      var index = 2;
      while (used.contains('$name$index')) {
        index++;
      }
      name = '$name$index';
    }
    return name;
  }

  String _clientMethodNameOf(Method method) {
    final name = pascalCase(method.name);
    if (name.isEmpty || RegExp(r'^[0-9]').hasMatch(name)) {
      return 'Call$name';
    }
    return name;
  }

  /// The name of the function that reads the entry of the map of a field.
  String _mapEntryName(Message message, Field field) =>
      'read${message.dartName}${_goFieldName(message, field)}Entry';
}

/// The kind of a Go type of a contract.
enum _GoKind { scalar, bytes, message, enumeration }

/// A Go type of a contract.
class _GoType {
  /// Creates a type.
  const _GoType({required this.name, required this.kind});

  /// The name of the type, as it is written in Go.
  final String name;

  /// The kind of the type.
  final _GoKind kind;

  /// Whether the type is a message.
  bool get isMessage => kind == _GoKind.message;

  /// Whether the type is an enum.
  bool get isEnum => kind == _GoKind.enumeration;
}

/// The way a scalar type of a contract is written on the wire.
class _GoEncoding {
  /// Creates an encoding.
  const _GoEncoding({
    required this.writer,
    required this.reader,
    required this.wireType,
    required this.packable,
    required this.unpack,
    required this.rawWriter,
    required this.write,
    required this.read,
  });

  /// The method of the writer that writes the value of the field.
  final String writer;

  /// The method of the reader that reads the value of the field.
  final String reader;

  /// The type of the value on the wire.
  final String wireType;

  /// Whether the values of the field are written packed.
  final bool packable;

  /// The method of the codec that reads the values of a packed field.
  final String unpack;

  /// The method of the writer that writes a value of a packed field.
  final String rawWriter;

  /// The code that writes the value of the field.
  final String Function(String) write;

  /// The code that reads the value of the field.
  final String Function(String) read;
}

/// The way a scalar type of a contract is written on the wire.
_GoEncoding _encodingOf(String protoType) {
  switch (protoType) {
    case 'string':
      return const _GoEncoding(
        writer: 'WriteString',
        reader: 'ReadString',
        wireType: 'wire.TypeBytes',
        packable: false,
        unpack: '',
        rawWriter: '',
        write: _identity,
        read: _identity,
      );
    case 'bytes':
      return const _GoEncoding(
        writer: 'WriteBytes',
        reader: 'ReadBytes',
        wireType: 'wire.TypeBytes',
        packable: false,
        unpack: '',
        rawWriter: '',
        write: _identity,
        read: _identity,
      );
    case 'bool':
      return const _GoEncoding(
        writer: 'WriteBool',
        reader: 'ReadBool',
        wireType: 'wire.TypeVarint',
        packable: false,
        unpack: '',
        rawWriter: '',
        write: _identity,
        read: _identity,
      );
    case 'int32':
      return const _GoEncoding(
        writer: 'WriteInt32',
        reader: 'ReadInt32',
        wireType: 'wire.TypeVarint',
        packable: true,
        unpack: 'UnpackInt32',
        rawWriter: 'WriteRawVarint',
        write: _identity,
        read: _identity,
      );
    case 'int64':
      return const _GoEncoding(
        writer: 'WriteInt64',
        reader: 'ReadInt64',
        wireType: 'wire.TypeVarint',
        packable: true,
        unpack: 'UnpackInt64',
        rawWriter: 'WriteRawVarint',
        write: _identity,
        read: _identity,
      );
    case 'uint32':
      return const _GoEncoding(
        writer: 'WriteUint32',
        reader: 'ReadUint32',
        wireType: 'wire.TypeVarint',
        packable: true,
        unpack: 'UnpackUint32',
        rawWriter: 'WriteRawVarint',
        write: _identity,
        read: _identity,
      );
    case 'uint64':
      return const _GoEncoding(
        writer: 'WriteUint64',
        reader: 'ReadUint64',
        wireType: 'wire.TypeVarint',
        packable: true,
        unpack: 'UnpackUint64',
        rawWriter: 'WriteRawVarint',
        write: _identity,
        read: _identity,
      );
    case 'sint32':
      return const _GoEncoding(
        writer: 'WriteSint32',
        reader: 'ReadSint32',
        wireType: 'wire.TypeVarint',
        packable: true,
        unpack: 'UnpackSint32',
        rawWriter: 'WriteRawSint32',
        write: _identity,
        read: _identity,
      );
    case 'sint64':
      return const _GoEncoding(
        writer: 'WriteSint64',
        reader: 'ReadSint64',
        wireType: 'wire.TypeVarint',
        packable: true,
        unpack: 'UnpackSint64',
        rawWriter: 'WriteRawSint64',
        write: _identity,
        read: _identity,
      );
    case 'fixed32':
      return const _GoEncoding(
        writer: 'WriteFixed32',
        reader: 'ReadFixed32',
        wireType: 'wire.TypeFixed32',
        packable: true,
        unpack: 'UnpackFixed32',
        rawWriter: 'WriteRawFixed32',
        write: _identity,
        read: _identity,
      );
    case 'fixed64':
      return const _GoEncoding(
        writer: 'WriteFixed64',
        reader: 'ReadFixed64',
        wireType: 'wire.TypeFixed64',
        packable: true,
        unpack: 'UnpackFixed64',
        rawWriter: 'WriteRawFixed64',
        write: _identity,
        read: _identity,
      );
    case 'sfixed32':
      return const _GoEncoding(
        writer: 'WriteFixed32',
        reader: 'ReadFixed32',
        wireType: 'wire.TypeFixed32',
        packable: true,
        unpack: 'UnpackFixed32',
        rawWriter: 'WriteRawFixed32',
        write: _toUint32,
        read: _toInt32,
      );
    case 'sfixed64':
      return const _GoEncoding(
        writer: 'WriteFixed64',
        reader: 'ReadFixed64',
        wireType: 'wire.TypeFixed64',
        packable: true,
        unpack: 'UnpackFixed64',
        rawWriter: 'WriteRawFixed64',
        write: _toUint64,
        read: _toInt64,
      );
    case 'float':
      return const _GoEncoding(
        writer: 'WriteFloat',
        reader: 'ReadFloat',
        wireType: 'wire.TypeFixed32',
        packable: true,
        unpack: 'UnpackFloat',
        rawWriter: 'WriteRawFloat',
        write: _identity,
        read: _identity,
      );
    case 'double':
      return const _GoEncoding(
        writer: 'WriteDouble',
        reader: 'ReadDouble',
        wireType: 'wire.TypeFixed64',
        packable: true,
        unpack: 'UnpackDouble',
        rawWriter: 'WriteRawDouble',
        write: _identity,
        read: _identity,
      );
    default:
      throw StateError('Unknown contract type "$protoType"');
  }
}

String _identity(String expression) => expression;

String _toUint32(String expression) => 'uint32($expression)';

String _toUint64(String expression) => 'uint64($expression)';

String _toInt32(String expression) => 'int32($expression)';

String _toInt64(String expression) => 'int64($expression)';

/// A field of a well-known type.
class _WellKnownField {
  /// Creates a field.
  const _WellKnownField(
    this.name,
    this.number,
    this.type,
    this.doc, {
    this.protoType = 'string',
  });

  /// The name of the field.
  final String name;

  /// The number of the field on the wire.
  final int number;

  /// The Go type of the field.
  final String type;

  /// The documentation of the field.
  final String doc;

  /// The type of the field as it is written in a contract.
  final String protoType;
}

/// The writer of the Go code.
class _GoWriter {
  final List<String> _lines = <String>[];
  int _depth = 0;

  /// Writes a line of code.
  void write(String line) {
    _lines.add('${'\t' * _depth}$line');
  }

  /// Writes an empty line.
  void blank() {
    _lines.add('');
  }

  /// Adds a level of indentation.
  void indent() {
    _depth++;
  }

  /// Removes a level of indentation.
  void dedent() {
    _depth--;
  }

  /// The code written so far.
  String get text {
    while (_lines.isNotEmpty && _lines.last.isEmpty) {
      _lines.removeLast();
    }
    return '${_lines.join('\n')}\n';
  }
}

/// Lowers the first letter of [value].
String _lowerFirst(String value) {
  if (value.isEmpty) {
    return value;
  }
  return value[0].toLowerCase() + value.substring(1);
}

/// Puts the article in front of [value], unless it has one already.
String _withArticle(String value) {
  for (final article in <String>['the ', 'a ', 'an ']) {
    if (value.startsWith(article)) {
      return value;
    }
  }
  return 'the $value';
}

/// The name of the constant of the value [value] of an enum.
///
/// The values of an enum are written in upper case in a contract, and Go
/// writes the names of its constants in PascalCase.
String _goConstantName(String value) {
  final buffer = StringBuffer();
  for (final word in _goWords(value)) {
    final lower = word.toLowerCase();
    buffer.write(lower[0].toUpperCase());
    buffer.write(lower.substring(1));
  }
  return buffer.toString();
}

/// Splits [value] into the words it is written with.
List<String> _goWords(String value) {
  final words = <String>[];
  final buffer = StringBuffer();

  for (var i = 0; i < value.length; i++) {
    final char = value[i];
    if (char == '_' || char == '-' || char == ' ') {
      if (buffer.isNotEmpty) {
        words.add(buffer.toString());
        buffer.clear();
      }
      continue;
    }
    final isUpper = char.toUpperCase() == char && char.toLowerCase() != char;
    final previous = i > 0 ? value[i - 1] : '';
    final previousIsLower = previous.toLowerCase() == previous &&
        previous.toUpperCase() != previous;
    if (isUpper && buffer.isNotEmpty && previousIsLower) {
      words.add(buffer.toString());
      buffer.clear();
    }
    buffer.write(char);
  }
  if (buffer.isNotEmpty) {
    words.add(buffer.toString());
  }
  return words;
}
