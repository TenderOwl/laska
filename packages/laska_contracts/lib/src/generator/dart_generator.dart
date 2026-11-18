import 'package:dart_style/dart_style.dart';

import '../model.dart';
import '../naming.dart';
import '../types.dart';

/// A file produced by a generator.
class GeneratedFile {
  /// Creates a generated file.
  GeneratedFile(this.path, this.content);

  /// Path of the file, relative to the output directory.
  final String path;

  /// Content of the file.
  final String content;
}

/// Generates Dart code out of a [Contract].
///
/// For every `.proto` file one `<name>.pb.dart` file is produced, holding
/// the message classes, the service interfaces, the REST projection of every
/// service and a typed client.
class DartGenerator {
  /// Creates a generator for [contract].
  DartGenerator(this.contract);

  /// The contract to generate code for.
  final Contract contract;

  late final TypeResolver _types = TypeResolver(contract);

  /// Generates the Dart files of the contract.
  List<GeneratedFile> generate() {
    final files = <GeneratedFile>[];
    for (final file in contract.files) {
      files.add(
        GeneratedFile(outputPathOf(file.path), _format(_generateFile(file))),
      );
    }
    return files;
  }

  /// Formats generated code so it matches `dart format`.
  ///
  /// Formatting doubles as a syntax check: a generator bug surfaces here
  /// instead of in the consumer's build.
  String _format(String source) {
    try {
      return DartFormatter(
        languageVersion: DartFormatter.latestLanguageVersion,
      ).format(source);
    } on FormatterException catch (error) {
      throw StateError(
        'Generated code is not valid Dart: ${error.message}',
      );
    }
  }

  /// Returns the output path of the Dart file generated for [protoPath].
  static String outputPathOf(String protoPath) =>
      protoPath.replaceAll(RegExp(r'\.proto$'), '.pb.dart');

  String _generateFile(ProtoFile file) {
    final writer = _Writer();
    final messages = file.messages;
    final enums = file.enums;
    final services = file.services;

    writer.write('// GENERATED CODE - DO NOT MODIFY BY HAND.');
    writer.write('//');
    writer.write('// Source: ${file.path}');
    writer.write('// Regenerate with: laska contract compile');
    writer.blank();

    final referenced = _referencedTypes(file);
    final needsJson = messages.isNotEmpty || services.isNotEmpty;
    final needsCore = services.isNotEmpty || messages.isNotEmpty;
    final needsHttp = services.any((service) => service.methods.isNotEmpty);

    if (needsJson) {
      writer.write("import 'dart:convert';");
      writer.blank();
    }
    if (needsHttp) {
      writer.write("import 'package:http/http.dart' as http;");
    }
    if (needsCore) {
      writer.write("import 'package:laska_core/laska_core.dart';");
    }
    for (final import in referenced.imports) {
      writer.write("import '$import';");
    }
    if (needsJson || needsCore || needsHttp || referenced.imports.isNotEmpty) {
      writer.blank();
    }

    if (enums.isNotEmpty) {
      writer.write('// Enums');
      writer.blank();
      for (final enumType in enums) {
        _writeEnum(writer, enumType);
        writer.blank();
      }
    }

    if (_needsEnumNumber(services)) {
      writer.write(
        '/// Reads the number of an enum value out of the bytes of the wire',
      );
      writer.write('/// format of the protocol buffers.');
      writer.write('int _enumNumber(List<int> bytes) {');
      writer.indent();
      writer.write('final reader = ProtoReader(bytes);');
      writer.write('return reader.hasNext ? reader.readVarint() : 0;');
      writer.dedent();
      writer.write('}');
      writer.blank();
    }

    if (messages.isNotEmpty) {
      writer.write('// Messages');
      writer.blank();
      for (final message in messages) {
        _writeMessage(writer, message);
        writer.blank();
      }
    }

    for (final service in services) {
      writer.write('// Service ${service.name}');
      writer.blank();
      _writeServiceInterface(writer, service);
      writer.blank();
      if (service.methods.any((method) => method.httpRules.isNotEmpty)) {
        _writeRouter(writer, service);
        writer.blank();
      }
      if (_hasPolicies(service)) {
        _writePolicies(writer, service);
        writer.blank();
      }
      if (service.methods.any((method) => method.httpRules.isNotEmpty)) {
        _writeClient(writer, service);
        writer.blank();
      }
    }

    return writer.text;
  }

  /// Whether the service declares a policy for one of its methods.
  bool _hasPolicies(Service service) => service.methods.any(
        (method) => !_policyOf(service, method).isEmpty,
      );

  /// Whether one of the methods of the services answers with an enum.
  bool _needsEnumNumber(List<Service> services) {
    for (final service in services) {
      for (final method in service.methods) {
        if (_types.findEnum(method.responseType) != null) {
          return true;
        }
      }
    }
    return false;
  }

  /// Writes the policies of the methods of the service.
  void _writePolicies(_Writer writer, Service service) {
    final name = pascalCase(service.name);
    writer.write('/// The policies of the methods of the `$name` service.');
    writer.write('///');
    writer.write(
        '/// The policies come from the `laska.policy` annotations of the');
    writer
        .write('/// contract, so the way a method is called is visible in the');
    writer.write('/// contract itself and not only in the code of the caller.');
    writer.write('class ${name}Policies {');
    writer.indent();
    writer.write('const ${name}Policies._();');
    writer.blank();

    for (final method in service.methods) {
      final policy = _policyOf(service, method);
      if (policy.isEmpty) {
        continue;
      }
      writer.write('/// The policy of the `${method.name}` method.');
      writer.write(
        'static final DependencyPolicy ${camelCase(method.name)} =',
      );
      writer.indent();
      writer.write('${_policyExpression(policy)};');
      writer.dedent();
      writer.blank();
    }

    writer.write('/// The policies of the methods, by the name of the method.');
    writer.write(
      'static final Map<String, DependencyPolicy> policies =',
    );
    writer.indent();
    writer.write('<String, DependencyPolicy>{');
    for (final method in service.methods) {
      final policy = _policyOf(service, method);
      if (policy.isEmpty) {
        continue;
      }
      writer.write("'${method.name}': ${camelCase(method.name)},");
    }
    writer.write('};');
    writer.dedent();
    writer.dedent();
    writer.write('}');
  }

  /// The policy of a method, with the policy of the service under it.
  MethodPolicy _policyOf(Service service, Method method) {
    final servicePolicy = service.policy;
    final methodPolicy = method.policy;
    if (servicePolicy == null) {
      return methodPolicy ?? MethodPolicy();
    }
    return servicePolicy.merge(methodPolicy);
  }

  /// The code of a policy of the contract.
  String _policyExpression(MethodPolicy policy) {
    final parts = <String>[];

    if (policy.timeout != null) {
      parts.add('timeout: ${_durationExpression(policy.timeout!)}');
    }

    final retry = <String>[];
    if (policy.maxAttempts != null) {
      retry.add('maxAttempts: ${policy.maxAttempts}');
    }
    if (policy.backoff != null) {
      retry.add('initialBackoff: ${_durationExpression(policy.backoff!)}');
    }
    if (policy.maxBackoff != null) {
      retry.add('maxBackoff: ${_durationExpression(policy.maxBackoff!)}');
    }
    if (policy.jitter != null) {
      retry.add('jitter: ${policy.jitter}');
    }
    if (retry.isNotEmpty) {
      parts.add('retry: RetryPolicy(${retry.join(', ')})');
    }

    if (policy.idempotent != null) {
      parts.add('idempotent: ${policy.idempotent}');
    }

    return 'DependencyPolicy(${parts.join(', ')})';
  }

  /// The code of a duration.
  String _durationExpression(Duration duration) {
    if (duration.inMilliseconds % 1000 == 0) {
      return 'Duration(seconds: ${duration.inSeconds})';
    }
    return 'Duration(milliseconds: ${duration.inMilliseconds})';
  }

  void _writeEnum(_Writer writer, EnumType enumType) {
    final name = pascalCase(enumType.name);
    _writeDoc(writer, enumType.comment, name);

    writer.write('enum $name {');
    writer.indent();
    for (var i = 0; i < enumType.values.length; i++) {
      final value = enumType.values[i];
      final constant = enumConstantName(value.name);
      final separator = i == enumType.values.length - 1 ? ';' : ',';
      _writeDoc(writer, value.comment, null);
      writer.write(
        "$constant('${value.name}', number: ${value.number})$separator",
      );
    }
    writer.blank();
    writer.write('const $name(this.protoName, {this.number = 0});');
    writer.blank();
    writer.write('/// The name of the value in the contract.');
    writer.write('final String protoName;');
    writer.blank();
    writer.write('/// The number of the value on the wire.');
    writer.write('final int number;');
    writer.blank();
    writer.write('/// Parses [raw] into a $name value.');
    writer.write('static $name fromName(Object? raw, {String? field}) {');
    writer.indent();
    writer.write('if (raw is String) {');
    writer.indent();
    writer.write('for (final value in $name.values) {');
    writer.indent();
    writer.write('if (value.protoName == raw || value.name == raw) {');
    writer.indent();
    writer.write('return value;');
    writer.dedent();
    writer.write('}');
    writer.dedent();
    writer.write('}');
    writer.dedent();
    writer.write('}');
    writer.write('if (field != null) {');
    writer.indent();
    writer.write(
      "throw FormatException('Unknown $name value for \$field: \$raw');",
    );
    writer.dedent();
    writer.write('}');
    writer.write("throw FormatException('Unknown $name value: \$raw');");
    writer.dedent();
    writer.write('}');
    writer.blank();
    writer.write('/// Reads the value of the number [number].');
    writer.write('static $name fromNumber(int number) {');
    writer.indent();
    writer.write('for (final value in $name.values) {');
    writer.indent();
    writer.write('if (value.number == number) {');
    writer.indent();
    writer.write('return value;');
    writer.dedent();
    writer.write('}');
    writer.dedent();
    writer.write('}');
    writer.write(
      'return $name.${enumConstantName(enumType.values.first.name)};',
    );
    writer.dedent();
    writer.write('}');
    writer.dedent();
    writer.write('}');
  }

  void _writeMessage(_Writer writer, Message message) {
    final name = pascalCase(message.name);
    _writeDoc(writer, message.comment, name);

    writer.write('class $name {');
    writer.indent();
    writer.write('/// Creates a $name.');
    writer.write('const $name({');
    writer.indent();
    for (final field in message.fields) {
      writer.write('${_constructorParameter(field)},');
    }
    writer.dedent();
    writer.write('});');
    writer.blank();

    for (final field in message.fields) {
      final type = _types.resolve(field);
      final dartType = field.optional && !field.repeated
          ? '${type.dartType}?'
          : type.dartType;
      _writeDoc(writer, field.comment, null);
      writer.write('final $dartType ${camelCase(field.name)};');
    }
    writer.blank();

    writer.write('/// Builds a $name from its JSON representation.');
    writer.write('factory $name.fromJson(Map<String, dynamic> json) {');
    writer.indent();
    for (final field in message.fields) {
      _writeFieldParser(writer, message, field);
    }
    writer.write('return $name(');
    writer.indent();
    for (final field in message.fields) {
      writer.write('${camelCase(field.name)}: ${_fieldValue(field)},');
    }
    writer.dedent();
    writer.write(');');
    writer.dedent();
    writer.write('}');
    writer.blank();

    writer.write('/// The JSON representation of the $name.');
    writer.write('Map<String, dynamic> toJson() => <String, dynamic>{');
    writer.indent();
    for (final field in message.fields) {
      final type = _types.resolve(field);
      final key = camelCase(field.name);
      final property = camelCase(field.name);
      if (type.isEnum && !field.repeated) {
        writer.write("'$key': $property.protoName,");
      } else if (type.isEnum && field.repeated) {
        writer
            .write("'$key': $property.map((item) => item.protoName).toList(),");
      } else if (type.isMessage && !field.repeated) {
        writer.write("'$key': $property.toJson(),");
      } else if (type.isMessage && field.repeated) {
        writer.write(
          "'$key': $property.map((item) => item.toJson()).toList(),",
        );
      } else if (field.optional && !field.repeated) {
        writer.write("if ($property != null) '$key': $property,");
      } else {
        writer.write("'$key': $property,");
      }
    }
    writer.dedent();
    writer.write('};');
    writer.dedent();
    writer.blank();

    _writeProtoWriter(writer, message);
    _writeProtoReader(writer, message);

    writer.dedent();
    writer.write('}');
  }

  /// Writes the method that holds the bytes of the message.
  void _writeProtoWriter(_Writer writer, Message message) {
    writer.write(
      '/// The bytes of the message in the wire format of the protocol buffers.',
    );
    writer.write('List<int> toProtoBytes() {');
    writer.indent();
    writer.write('final writer = ProtoWriter();');
    for (final field in message.fields) {
      _writeProtoValue(writer, message, field);
    }
    writer.write('return writer.toBytes();');
    writer.dedent();
    writer.write('}');
    writer.blank();
  }

  /// Writes the method that reads the message out of its bytes.
  void _writeProtoReader(_Writer writer, Message message) {
    final name = pascalCase(message.name);
    writer.write(
      '/// Reads a message out of the wire format of the protocol buffers.',
    );
    writer.write('factory $name.fromProtoBytes(List<int> bytes) {');
    writer.indent();
    writer.write('final reader = ProtoReader(bytes);');

    for (final field in message.fields) {
      final type = _types.resolve(field);
      final property = camelCase(field.name);
      if (field.repeated) {
        writer.write('var $property = <${_elementType(type.dartType)}>[];');
      } else if (field.optional) {
        writer.write('var $property = <${type.dartType}>?;');
      } else if (type.isMessage) {
        writer.write('var $property = <${type.dartType}>?;');
      } else if (type.isEnum) {
        writer.write(
          'var $property = ${type.enumName}.'
          '${enumConstantName(_enumOf(type).values.first.name)};',
        );
      } else {
        writer.write('var $property = ${_defaultOf(type)};');
      }
    }
    writer.blank();

    writer.write('while (reader.hasNext) {');
    writer.indent();
    writer.write('final tag = reader.readTag();');
    writer.write('switch (tag) {');
    for (final field in message.fields) {
      writer.write('case ${field.number}:');
      writer.indent();
      _writeProtoRead(writer, message, field);
      writer.dedent();
    }
    writer.write('default:');
    writer.indent();
    writer.write('reader.skipField();');
    writer.dedent();
    writer.dedent();
    writer.write('}');
    writer.dedent();
    writer.write('}');
    writer.blank();

    for (final field in message.fields) {
      final type = _types.resolve(field);
      if (type.isMessage && !field.repeated && !field.optional) {
        final property = camelCase(field.name);
        writer.write('if ($property == null) {');
        writer.indent();
        writer.write(
          "throw FormatException("
          "'The message \"$name\" needs the field \"$property\".');",
        );
        writer.dedent();
        writer.write('}');
      }
    }

    writer.write('return $name(');
    writer.indent();
    for (final field in message.fields) {
      final property = camelCase(field.name);
      writer.write('$property: $property,');
    }
    writer.dedent();
    writer.write(');');
    writer.dedent();
    writer.write('}');
  }

  /// Writes the code that puts the value of a field on the wire.
  void _writeProtoValue(_Writer writer, Message message, Field field) {
    final type = _types.resolve(field);
    final property = camelCase(field.name);
    final number = field.number;

    if (field.repeated) {
      writer.write('for (final item in $property) {');
      writer.indent();
      if (type.isMessage) {
        writer.write(
          'writer.writeMessage($number, item.toProtoBytes());',
        );
      } else if (type.isEnum) {
        writer.write('writer.writeEnum($number, item.number);');
      } else {
        writer.write('writer.${_protoWriterOf(type)}($number, item);');
      }
      writer.dedent();
      writer.write('}');
      return;
    }

    if (field.optional) {
      writer.write('if ($property != null) {');
      writer.indent();
      if (type.isMessage) {
        writer.write(
          'writer.writeMessage($number, $property!.toProtoBytes());',
        );
      } else if (type.isEnum) {
        writer.write('writer.writeEnum($number, $property!.number);');
      } else {
        writer.write('writer.${_protoWriterOf(type)}($number, $property!);');
      }
      writer.dedent();
      writer.write('}');
      return;
    }

    if (type.isMessage) {
      writer.write('writer.writeMessage($number, $property.toProtoBytes());');
      return;
    }

    if (type.isEnum) {
      writer.write('if ($property.number != 0) {');
      writer.indent();
      writer.write('writer.writeEnum($number, $property.number);');
      writer.dedent();
      writer.write('}');
      return;
    }

    writer.write('if ($property != ${_defaultOf(type)}) {');
    writer.indent();
    writer.write('writer.${_protoWriterOf(type)}($number, $property);');
    writer.dedent();
    writer.write('}');
  }

  /// Writes the code that reads the value of a field from the wire.
  void _writeProtoRead(_Writer writer, Message message, Field field) {
    final type = _types.resolve(field);
    final property = camelCase(field.name);

    if (field.repeated) {
      if (type.isMessage) {
        writer.write(
          '$property.add('
          '${type.messageName}.fromProtoBytes(reader.readBytes()));',
        );
        return;
      }
      if (type.isEnum) {
        writer.write(
          '$property.addAll('
          'reader.readRepeatedVarint(<int>[]).map(${type.enumName}.fromNumber));',
        );
        return;
      }
      if (type.protoType == 'bool') {
        writer.write(
          '$property.addAll('
          'reader.readRepeatedVarint(<int>[]).map((value) => value != 0));',
        );
        return;
      }
      if (type.protoType == 'string') {
        writer.write('$property.add(reader.readString());');
        return;
      }
      if (type.protoType == 'bytes') {
        writer.write('$property.add(reader.readBytes());');
        return;
      }
      writer.write(
        '$property.addAll(reader.${_protoRepeatedReaderOf(type)}(<int>[]));',
      );
      return;
    }

    if (type.isMessage) {
      writer.write(
        '$property = ${type.messageName}.fromProtoBytes(reader.readBytes());',
      );
      return;
    }

    if (type.isEnum) {
      writer
          .write('$property = ${type.enumName}.fromNumber(reader.readEnum());');
      return;
    }

    writer.write('$property = reader.${_protoReaderOf(type)}();');
  }

  /// The method of the writer that writes a value of the type [type].
  String _protoWriterOf(DartType type) {
    switch (type.protoType) {
      case 'string':
        return 'writeString';
      case 'bytes':
        return 'writeBytes';
      case 'bool':
        return 'writeBool';
      case 'int32':
        return 'writeInt32';
      case 'int64':
        return 'writeInt64';
      case 'uint32':
        return 'writeUInt32';
      case 'uint64':
        return 'writeUInt64';
      case 'sint32':
        return 'writeSInt32';
      case 'sint64':
        return 'writeSInt64';
      case 'fixed32':
        return 'writeFixed32';
      case 'fixed64':
        return 'writeFixed64';
      case 'sfixed32':
        return 'writeSFixed32';
      case 'sfixed64':
        return 'writeSFixed64';
      case 'float':
        return 'writeFloat';
      case 'double':
        return 'writeDouble';
      default:
        throw StateError('Unknown contract type "${type.protoType}"');
    }
  }

  /// The method of the reader that reads a value of the type [type].
  String _protoReaderOf(DartType type) {
    switch (type.protoType) {
      case 'string':
        return 'readString';
      case 'bytes':
        return 'readBytes';
      case 'bool':
        return 'readBool';
      case 'int32':
        return 'readInt32';
      case 'int64':
        return 'readInt64';
      case 'uint32':
        return 'readInt32';
      case 'uint64':
        return 'readInt64';
      case 'sint32':
        return 'readSInt32';
      case 'sint64':
        return 'readSInt64';
      case 'fixed32':
        return 'readFixed32';
      case 'fixed64':
        return 'readFixed64';
      case 'sfixed32':
        return 'readSFixed32';
      case 'sfixed64':
        return 'readSFixed64';
      case 'float':
        return 'readFloat';
      case 'double':
        return 'readDouble';
      default:
        throw StateError('Unknown contract type "${type.protoType}"');
    }
  }

  /// The method of the reader that reads a repeated value of the type [type].
  String _protoRepeatedReaderOf(DartType type) {
    switch (type.protoType) {
      case 'int32':
      case 'int64':
      case 'uint32':
      case 'uint64':
        return 'readRepeatedVarint';
      case 'sint32':
        return 'readRepeatedSInt32';
      case 'sint64':
        return 'readRepeatedSInt64';
      case 'fixed32':
      case 'sfixed32':
        return 'readRepeatedFixed32';
      case 'fixed64':
      case 'sfixed64':
        return 'readRepeatedFixed64';
      case 'float':
        return 'readRepeatedFloat';
      case 'double':
        return 'readRepeatedDouble';
      default:
        throw StateError('Unknown contract type "${type.protoType}"');
    }
  }

  /// The default value of the type [type].
  String _defaultOf(DartType type) {
    switch (type.dartType) {
      case 'String':
        return "''";
      case 'bool':
        return 'false';
      case 'int':
        return '0';
      case 'double':
        return '0.0';
      case 'List<int>':
        return 'const <int>[]';
      default:
        throw StateError('Unknown contract type "${type.dartType}"');
    }
  }

  /// The enum of the type [type].
  EnumType _enumOf(DartType type) {
    final enumType = _types.findEnum(type.protoType);
    if (enumType == null) {
      throw StateError('Unknown enum "${type.protoType}"');
    }
    return enumType;
  }

  void _writeFieldParser(_Writer writer, Message message, Field field) {
    final type = _types.resolve(field);
    final key = camelCase(field.name);
    final name = pascalCase(message.name);
    final property = camelCase(field.name);

    if (type.isEnum && !field.repeated) {
      writer.write(
        "final ${property}Value = ${type.enumName}.fromName(json['$key'], field: '$name.$key');",
      );
      return;
    }

    if (field.repeated) {
      writer.write("final $property = json['$key'];");
      writer.write("if ($property != null && $property is! List) {");
      writer.indent();
      writer.write(
        "throw const FormatException('$name.$key must be a list');",
      );
      writer.dedent();
      writer.write('}');
      if (type.isEnum) {
        writer.write(
          'final ${property}Value = $property == null '
          '? const <${_elementType(type.dartType)}>[] '
          ': List<${_elementType(type.dartType)}>.from($property.map((item) => '
          '${type.enumName}.fromName(item, field: \'$name.$key\')));',
        );
      } else if (type.isMessage) {
        writer.write(
          'final ${property}Value = $property == null '
          '? const <${_elementType(type.dartType)}>[] '
          ': List<${_elementType(type.dartType)}>.from($property.map((item) => '
          '${type.messageName}.fromJson(item as Map<String, dynamic>)));',
        );
      }
      return;
    }

    writer.write("final $property = json['$key'];");

    if (field.optional) {
      writer
          .write("if ($property != null && $property is! ${type.dartType}) {");
      writer.indent();
      writer.write(
        "throw const FormatException('$name.$key must be of type "
        "${type.dartType}');",
      );
      writer.dedent();
      writer.write('}');
      return;
    }

    if (type.isMessage) {
      writer.write("if ($property is! Map<String, dynamic>) {");
      writer.indent();
      writer.write(
        "throw const FormatException('$name.$key must be an object');",
      );
      writer.dedent();
      writer.write('}');
      writer.write(
        'final ${property}Value = ${type.messageName}.fromJson($property);',
      );
      return;
    }

    writer.write("if ($property is! ${type.dartType}) {");
    writer.indent();
    writer.write(
      "throw const FormatException('$name.$key must be of type "
      "${type.dartType}');",
    );
    writer.dedent();
    writer.write('}');
  }

  String _fieldValue(Field field) {
    final type = _types.resolve(field);
    final property = camelCase(field.name);
    if (type.isEnum || type.isMessage) {
      return '${property}Value';
    }
    if (field.repeated) {
      final element = _elementType(type.dartType);
      return '$property == null ? const <$element>[] '
          ': List<$element>.from($property.map((item) => item as $element))';
    }
    if (field.optional) {
      return '$property as ${type.dartType}?';
    }
    return property;
  }

  String _constructorParameter(Field field) {
    final type = _types.resolve(field);
    final property = camelCase(field.name);
    if (field.repeated) {
      final element = _elementType(type.dartType);
      return 'this.$property = const <$element>[]';
    }
    if (field.optional) {
      return 'this.$property';
    }
    return 'required this.$property';
  }

  void _writeServiceInterface(_Writer writer, Service service) {
    final name = pascalCase(service.name);
    _writeDoc(writer, service.comment, 'Service `${service.fullName}`.');
    writer.write('abstract class $name {');
    writer.indent();
    for (final method in service.methods) {
      _writeDoc(writer, method.comment, null);
      final request = _types.resolve(_requestField(method));
      final response = _types.resolve(_responseField(method));
      writer.write(
        'Future<${response.dartType}> ${camelCase(method.name)}'
        '(${request.dartType} request);',
      );
    }
    writer.dedent();
    writer.write('}');
  }

  void _writeRouter(_Writer writer, Service service) {
    final name = pascalCase(service.name);
    writer.write('/// Registers the REST projection of [service] on [app].');
    writer.write('void register$name(');
    writer.indent();
    writer.write('Laska app,');
    writer.write('$name service, {');
    writer.indent();
    writer.write('List<Middleware> middleware = const <Middleware>[],');
    writer.dedent();
    writer.write('}) {');
    writer.indent();

    for (final method in service.methods) {
      for (final rule in method.httpRules) {
        _writeRoute(writer, method, rule);
      }
    }

    writer.dedent();
    writer.dedent();
    writer.write('}');
  }

  void _writeRoute(_Writer writer, Method method, HttpRule rule) {
    final requestField = _requestField(method);
    final requestType = _types.resolve(requestField);
    final responseType = _types.resolve(_responseField(method));
    final methodName = camelCase(method.name);
    final pathParams = rule.pathParameters;

    writer.write('app.${rule.method.toLowerCase()}(');
    writer.indent();
    writer.write("'${_routePath(rule.path)}',");
    writer.write('(ctx) async {');
    writer.indent();
    writer.write('final payload = <String, dynamic>{};');

    if (rule.body != null) {
      if (rule.body == '*') {
        writer.write('payload.addAll(ctx.request.json());');
      } else {
        writer
            .write("payload['${camelCase(rule.body!)}'] = ctx.request.json();");
      }
    }

    final queryFields = <Field>[];
    for (final field in _fieldsOf(requestField)) {
      if (pathParams.contains(field.name)) {
        continue;
      }
      if (rule.body == '*' || rule.body == field.name) {
        continue;
      }
      queryFields.add(field);
    }

    final scalarQueryFields = queryFields.where((field) {
      final type = _types.resolve(field);
      return !type.isMessage && !type.isEnum;
    }).toList();

    if (scalarQueryFields.isNotEmpty) {
      writer.write('final query = ctx.query;');
      for (final field in scalarQueryFields) {
        final type = _types.resolve(field);
        final key = camelCase(field.name);
        writer.write("if (query.containsKey('$key')) {");
        writer.indent();
        writer.write(
          "payload['$key'] = ${_parseValue(type, "query['$key']!", key)};",
        );
        writer.dedent();
        writer.write('}');
      }
    }

    for (final parameter in pathParams) {
      final field = _fieldNamed(requestField, parameter);
      final type = field == null ? null : _types.resolve(field);
      final raw = "ctx.params['$parameter']!";
      if (type == null) {
        writer.write("payload['$parameter'] = $raw;");
      } else {
        writer.write(
          "payload['$parameter'] = ${_parseValue(type, raw, parameter)};",
        );
      }
    }

    writer.write('final request = ${requestType.dartType}.fromJson(payload);');
    writer.write('final response = await service.$methodName(request);');
    if (responseType.isEnum) {
      writer.write('return ctx.json(response.protoName);');
    } else {
      writer.write('return ctx.json(response.toJson());');
    }
    writer.dedent();
    writer.write('},');
    writer.write('middleware: middleware,');
    writer.dedent();
    writer.write(');');
    writer.blank();
  }

  void _writeClient(_Writer writer, Service service) {
    final name = pascalCase(service.name);
    writer.write('/// Typed client for the `$name` service.');
    writer.write('class ${name}Client {');
    writer.indent();
    writer.write('/// Creates a client talking to [baseUrl].');
    writer.write('${name}Client({');
    writer.indent();
    writer.write('required this.baseUrl,');
    writer.write('ServiceTransport? transport,');
    writer.write('http.Client? httpClient,');
    writer.write('Duration timeout = const Duration(seconds: 2),');
    writer.write('Tracer? tracer,');
    writer.write("String dependencyName = '${service.name}',");
    writer.write('DependencyPolicy policy = const DependencyPolicy(),');
    writer.write('Map<String, DependencyPolicy>? policies,');
    writer.dedent();
    writer.write('})  : _transport = transport ??');
    writer.indent();
    writer.write(
      'HttpServiceTransport(baseUrl: baseUrl, client: httpClient),',
    );
    writer.dedent();
    writer.write('      // ignore: prefer_initializing_formals');
    writer.write('      _timeout = timeout,');
    writer.write('      // ignore: prefer_initializing_formals');
    writer.write('      _tracer = tracer,');
    writer.write('      // ignore: prefer_initializing_formals');
    writer.write('      _dependencyName = dependencyName,');
    writer.write('      // ignore: prefer_initializing_formals');
    writer.write('      _policy = policy,');
    writer.write('      // ignore: prefer_initializing_formals');
    writer.write('      _policies = <String, DependencyPolicy>{');
    writer.write('        ...${name}Policies.policies,');
    writer.write('        ...?policies,');
    writer.write('      };');
    writer.blank();
    writer.write('/// Base URL of the service, e.g. `http://localhost:8080`.');
    writer.write('final String baseUrl;');
    writer.blank();
    writer.write('/// The transport the calls go through.');
    writer.write('final ServiceTransport _transport;');
    writer.blank();
    writer.write(
        '/// The timeout of the calls that have no policy of their own.');
    writer.write('final Duration _timeout;');
    writer.blank();
    writer.write('/// The tracer of the client, when the calls are traced.');
    writer.write('final Tracer? _tracer;');
    writer.blank();
    writer.write('/// The name of the dependency the calls go to.');
    writer.write('final String _dependencyName;');
    writer.blank();
    writer.write('/// The policy of the dependency.');
    writer.write('///');
    writer.write('/// It holds the circuit breaker and the bulkhead of the');
    writer.write('/// dependency, which every call of the client shares.');
    writer.write('final DependencyPolicy _policy;');
    writer.blank();
    writer.write('/// The policy of every method, by the name of the method.');
    writer.write('final Map<String, DependencyPolicy> _policies;');
    writer.blank();
    writer.write('/// The dependency the calls go through.');
    writer.write('///');
    writer
        .write('/// The dependency holds the circuit breaker and the bulkhead');
    writer
        .write('/// of the service, so every call of the client shares them.');
    writer.write('late final Dependency _dependency = Dependency(');
    writer.indent();
    writer.write('name: _dependencyName,');
    writer.write('transport: _transport,');
    writer.write('policy: _policy,');
    writer.write('tracer: _tracer,');
    writer.dedent();
    writer.write(');');
    writer.blank();

    for (final method in service.methods) {
      for (final rule in method.httpRules) {
        _writeClientMethod(writer, service, method, rule);
      }
    }

    _writeClientSend(writer);
    writer.dedent();
    writer.write('}');
  }

  /// Writes the method that sends the request of a method of the service.
  void _writeClientSend(_Writer writer) {
    writer.write('/// Sends the request of a method of the service.');
    writer.write('///');
    writer.write(
        '/// The policy of the method decides how the call is timed out,');
    writer.write(
        '/// how often it is retried and whether it may be retried at all.');
    writer.write('Future<TransportResponse> _send(');
    writer.indent();
    writer.write('String method,');
    writer.write('String operation,');
    writer.write('String verb,');
    writer.write('Uri uri,');
    writer.write('Map<String, String> headers,');
    writer.write('List<int>? body,');
    writer.dedent();
    writer.write(') async {');
    writer.indent();
    writer.write('final methodPolicy = _policies[method];');
    writer.write('final effectivePolicy = methodPolicy == null');
    writer.indent();
    writer.write('? DependencyPolicy(timeout: _timeout)');
    writer.write(': methodPolicy.copyWith(');
    writer.indent();
    writer.write('timeout: methodPolicy.timeout ?? _timeout,');
    writer.dedent();
    writer.write(');');
    writer.dedent();
    writer.write('try {');
    writer.indent();
    writer.write('return await _dependency.call(');
    writer.indent();
    writer.write('TransportRequest(');
    writer.indent();
    writer.write('method: verb,');
    writer.write('uri: uri,');
    writer.write('headers: headers,');
    writer.write('body: body,');
    writer.write('contentType: body == null');
    writer.indent();
    writer.write('? null');
    writer.write(': _transport.bodyFormat == BodyFormat.protobuf');
    writer.indent();
    writer.write('? "application/protobuf"');
    writer.write(': "application/json",');
    writer.dedent();
    writer.dedent();
    writer.write('),');
    writer.write('policy: effectivePolicy,');
    writer.write('operation: operation,');
    writer.write('attributes: <String, Object?>{');
    writer.indent();
    writer.write("'http.request.method': verb,");
    writer.write("'url.path': uri.path,");
    writer.dedent();
    writer.write('},');
    writer.dedent();
    writer.write(');');
    writer.dedent();
    writer.write('} on DependencyFailure catch (error) {');
    writer.indent();
    writer.write(
      'throw LaskaApiException(error.statusCode ?? 502, error.body);',
    );
    writer.dedent();
    writer.write('} on DependencyTimeoutException catch (error) {');
    writer.indent();
    writer.write('throw LaskaApiException(504, error.toString());');
    writer.dedent();
    writer.write('} on CircuitOpenException catch (error) {');
    writer.indent();
    writer.write('throw LaskaApiException(503, error.toString());');
    writer.dedent();
    writer.write('} on BulkheadFullException catch (error) {');
    writer.indent();
    writer.write('throw LaskaApiException(503, error.toString());');
    writer.dedent();
    writer.write('}');
    writer.dedent();
    writer.write('}');
    writer.blank();
  }

  void _writeClientMethod(
    _Writer writer,
    Service service,
    Method method,
    HttpRule rule,
  ) {
    final requestField = _requestField(method);
    final requestType = _types.resolve(requestField);
    final responseType = _types.resolve(_responseField(method));
    final methodName = camelCase(method.name);
    final pathParams = rule.pathParameters;
    final policy = _policyOf(service, method);
    final idempotent = policy.idempotent ?? false;

    _writeDoc(writer, method.comment, null);
    writer.write(
      'Future<${responseType.dartType}> $methodName'
      '(${requestType.dartType} request, {String? idempotencyKey}) async {',
    );
    writer.indent();

    final queryFields = <Field>[];
    for (final field in _fieldsOf(requestField)) {
      if (pathParams.contains(field.name)) {
        continue;
      }
      if (rule.body == '*' || rule.body == field.name) {
        continue;
      }
      final type = _types.resolve(field);
      if (type.isMessage || type.isEnum) {
        continue;
      }
      queryFields.add(field);
    }

    if (queryFields.isNotEmpty) {
      writer.write('final query = <String, String>{};');
      for (final field in queryFields) {
        final key = camelCase(field.name);
        final property = camelCase(field.name);
        if (field.optional) {
          writer.write(
            "if (request.$property != null) query['$key'] = "
            'request.$property.toString();',
          );
        } else {
          writer.write("query['$key'] = request.$property.toString();");
        }
      }
      writer.blank();
    }

    final pathExpression = _pathExpression(rule, pathParams);
    writer.write('final uri = _transport.buildUri(');
    writer.indent();
    writer.write("'$pathExpression',");
    writer.write("'/${service.fullName}/${method.name}',");
    if (queryFields.isEmpty) {
      writer.dedent();
      writer.write(');');
    } else {
      writer.dedent();
      writer.write(').replace(');
      writer.indent();
      writer.write('queryParameters: query.isEmpty ? null : query,');
      writer.dedent();
      writer.write(');');
    }
    writer.blank();

    final verb = rule.method.toLowerCase();

    writer.write('final headers = <String, String>{');
    writer.indent();
    writer.write("'accept': 'application/json',");
    if (verb != 'get' && verb != 'delete') {
      writer.write("'content-type': 'application/json',");
    }
    writer.dedent();
    writer.write('};');
    writer.blank();

    if (idempotent) {
      writer.write('if (idempotencyKey != null) {');
      writer.indent();
      writer.write("headers['idempotency-key'] = idempotencyKey;");
      writer.dedent();
      writer.write('}');
    } else {
      writer.write('final key = idempotencyKey ?? newIdempotencyKey();');
      writer.write("headers['idempotency-key'] = key;");
    }
    writer.blank();

    if (rule.body != null) {
      final jsonExpression = rule.body == '*'
          ? 'request.toJson()'
          : 'request.${camelCase(rule.body!)}.toJson()';
      final protoExpression = rule.body == '*'
          ? 'request.toProtoBytes()'
          : 'request.${camelCase(rule.body!)}.toProtoBytes()';
      writer.write(
        'final body = _transport.bodyFormat == BodyFormat.protobuf',
      );
      writer.indent();
      writer.write('? $protoExpression');
      writer.write(': utf8.encode(jsonEncode($jsonExpression));');
      writer.dedent();
    } else {
      writer.write('final body = null;');
    }
    writer.blank();

    writer.write('final response = await _send(');
    writer.indent();
    writer.write("'${method.name}',");
    writer.write("'${service.name}.${method.name}',");
    writer.write("'$verb',");
    writer.write('uri,');
    writer.write('headers,');
    writer.write('body,');
    writer.dedent();
    writer.write(');');
    writer.blank();

    if (responseType.isEnum) {
      writer.write(
        'return _transport.bodyFormat == BodyFormat.protobuf',
      );
      writer.indent();
      writer.write(
        '? ${responseType.enumName}.fromNumber(_enumNumber(response.body))',
      );
      writer.write(
        ': ${responseType.enumName}.fromName(jsonDecode(response.text));',
      );
      writer.dedent();
    } else {
      writer.write(
        'return _transport.bodyFormat == BodyFormat.protobuf',
      );
      writer.indent();
      writer.write(
        '? ${responseType.dartType}.fromProtoBytes(response.body)',
      );
      writer.write(
        ': ${responseType.dartType}.fromJson('
        'jsonDecode(response.text) as Map<String, dynamic>);',
      );
      writer.dedent();
    }

    writer.dedent();
    writer.write('}');
    writer.blank();
  }

  /// Converts an OpenAPI style path template into a router pattern.
  ///
  /// `/v1/users/{id}` becomes `/v1/users/:id`.
  static String _routePath(String template) => template.replaceAllMapped(
        RegExp(r'\{([^}]+)\}'),
        (match) => ':${match.group(1)}',
      );

  String _pathExpression(HttpRule rule, List<String> pathParams) {
    final buffer = StringBuffer();
    var index = 0;
    final template = rule.path;
    for (final match in RegExp(r'\{([^}]+)\}').allMatches(template)) {
      buffer.write(template.substring(index, match.start));
      final parameter = match.group(1)!;
      buffer.write(
        '\${Uri.encodeComponent(request.${camelCase(parameter)}.toString())}',
      );
      index = match.end;
    }
    buffer.write(template.substring(index));
    return buffer.toString();
  }

  String _parseValue(DartType type, String raw, String name) {
    switch (type.dartType) {
      case 'int':
        return "parseIntValue($raw, '$name')";
      case 'double':
        return "parseDoubleValue($raw, '$name')";
      case 'bool':
        return "parseBoolValue($raw, '$name')";
      default:
        return raw;
    }
  }

  String _elementType(String dartType) {
    if (dartType.startsWith('List<') && dartType.endsWith('>')) {
      return dartType.substring(5, dartType.length - 1);
    }
    return dartType;
  }

  Field _requestField(Method method) {
    final message = _types.findMessage(method.requestType);
    if (message == null) {
      throw StateError('Unknown request type "${method.requestType}"');
    }
    return _syntheticField(message);
  }

  Field _responseField(Method method) {
    final message = _types.findMessage(method.responseType);
    if (message != null) {
      return _syntheticField(message);
    }
    final enumType = _types.findEnum(method.responseType);
    if (enumType == null) {
      throw StateError('Unknown response type "${method.responseType}"');
    }
    return Field(name: enumType.name, number: 0, type: enumType.name);
  }

  Field _syntheticField(Message message) =>
      Field(name: message.name, number: 0, type: message.fullName);

  List<Field> _fieldsOf(Field field) {
    final message = _types.findMessage(field.type);
    if (message == null) {
      return const <Field>[];
    }
    return message.fields;
  }

  Field? _fieldNamed(Field requestField, String name) {
    for (final field in _fieldsOf(requestField)) {
      if (field.name == name) {
        return field;
      }
    }
    return null;
  }

  _ReferencedTypes _referencedTypes(ProtoFile file) {
    final imports = <String>{};
    final ownMessages =
        file.messages.map((message) => message.fullName).toSet();
    final ownEnums = file.enums.map((value) => value.fullName).toSet();

    final referenced = <String>{};
    for (final message in file.messages) {
      for (final field in message.fields) {
        referenced.add(field.type);
      }
    }
    for (final service in file.services) {
      for (final method in service.methods) {
        referenced.add(method.requestType);
        referenced.add(method.responseType);
      }
    }

    for (final reference in referenced) {
      final message = _types.findMessage(reference);
      if (message != null) {
        if (!ownMessages.contains(message.fullName)) {
          imports.add(_importPath(file.path, message.fullName));
        }
        continue;
      }
      final enumType = _types.findEnum(reference);
      if (enumType != null && !ownEnums.contains(enumType.fullName)) {
        imports.add(_importPath(file.path, enumType.fullName));
      }
    }

    return _ReferencedTypes(imports.toList()..sort());
  }

  String _importPath(String fromProto, String referencedFullName) {
    final target = contract.files.firstWhere(
      (file) =>
          file.messages
              .any((message) => message.fullName == referencedFullName) ||
          file.enums.any((value) => value.fullName == referencedFullName),
    );
    return _relativePath(fromProto, outputPathOf(target.path));
  }

  /// Returns the path of [target] relative to the directory of [from].
  static String _relativePath(String from, String target) {
    final fromParts = from.split('/')..removeLast();
    final targetParts = target.split('/');

    var common = 0;
    while (common < fromParts.length &&
        common < targetParts.length - 1 &&
        fromParts[common] == targetParts[common]) {
      common++;
    }

    final up = List<String>.filled(fromParts.length - common, '..');
    final down = targetParts.sublist(common);
    return <String>[...up, ...down].join('/');
  }

  void _writeDoc(_Writer writer, String? comment, String? fallback) {
    final text = comment ?? fallback;
    if (text == null) {
      return;
    }
    for (final line in text.split('\n')) {
      final trimmed = line.trim();
      writer.write(trimmed.isEmpty ? '///' : '/// $trimmed');
    }
  }
}

class _ReferencedTypes {
  _ReferencedTypes(this.imports);

  final List<String> imports;
}

class _Writer {
  final StringBuffer _buffer = StringBuffer();
  int _indent = 0;

  void write(String line) {
    if (line.isEmpty) {
      _buffer.writeln();
      return;
    }
    _buffer.writeln('${'  ' * _indent}$line');
  }

  void blank() => _buffer.writeln();

  void indent() => _indent++;

  void dedent() => _indent--;

  String get text => _buffer.toString();
}
