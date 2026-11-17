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
    final needsCore = services.isNotEmpty;
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
        _writeClient(writer, service);
        writer.blank();
      }
    }

    return writer.text;
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
      writer.write("$constant('${value.name}')$separator");
    }
    writer.blank();
    writer.write('const $name(this.protoName);');
    writer.blank();
    writer.write('/// The name of the value in the contract.');
    writer.write('final String protoName;');
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
    writer.write('}');
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
    writer.write('http.Client? httpClient,');
    writer.write('Duration timeout = const Duration(seconds: 2),');
    writer.dedent();
    writer.write('})  : _http = httpClient ?? http.Client(),');
    writer.write('      // ignore: prefer_initializing_formals');
    writer.write('      _timeout = timeout;');
    writer.blank();
    writer.write('/// Base URL of the service, e.g. `http://localhost:8080`.');
    writer.write('final String baseUrl;');
    writer.blank();
    writer.write('final http.Client _http;');
    writer.write('final Duration _timeout;');
    writer.blank();

    for (final method in service.methods) {
      for (final rule in method.httpRules) {
        _writeClientMethod(writer, method, rule);
      }
    }

    writer.dedent();
    writer.write('}');
  }

  void _writeClientMethod(_Writer writer, Method method, HttpRule rule) {
    final requestField = _requestField(method);
    final requestType = _types.resolve(requestField);
    final responseType = _types.resolve(_responseField(method));
    final methodName = camelCase(method.name);
    final pathParams = rule.pathParameters;

    _writeDoc(writer, method.comment, null);
    writer.write(
      'Future<${responseType.dartType}> $methodName'
      '(${requestType.dartType} request) async {',
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
    if (queryFields.isEmpty) {
      writer.write("final uri = Uri.parse('\$baseUrl$pathExpression');");
    } else {
      writer.write(
        "final uri = Uri.parse('\$baseUrl$pathExpression').replace(",
      );
      writer.indent();
      writer.write('queryParameters: query.isEmpty ? null : query,');
      writer.dedent();
      writer.write(');');
    }
    writer.blank();

    final verb = rule.method.toLowerCase();
    if (verb == 'get' || verb == 'delete') {
      writer.write('final response = await _http');
      writer.indent();
      writer.write(
        ".$verb(uri, headers: const <String, String>{'accept': "
        "'application/json'})",
      );
      writer.write('.timeout(_timeout);');
      writer.dedent();
    } else {
      final bodyExpression = rule.body == '*'
          ? 'request.toJson()'
          : 'request.${camelCase(rule.body!)}.toJson()';
      writer.write('final response = await _http');
      writer.indent();
      writer.write('.$verb(');
      writer.indent();
      writer.write('uri,');
      writer.write('headers: const <String, String>{');
      writer.indent();
      writer.write("'accept': 'application/json',");
      writer.write("'content-type': 'application/json',");
      writer.dedent();
      writer.write('},');
      writer.write('body: jsonEncode($bodyExpression),');
      writer.dedent();
      writer.write(')');
      writer.write('.timeout(_timeout);');
      writer.dedent();
    }

    writer.write('if (response.statusCode >= 400) {');
    writer.indent();
    writer.write(
      'throw LaskaApiException(response.statusCode, response.body);',
    );
    writer.dedent();
    writer.write('}');

    if (responseType.isEnum) {
      writer.write(
        'return ${responseType.enumName}.fromName(jsonDecode(response.body));',
      );
    } else {
      writer.write(
        'return ${responseType.dartType}.fromJson('
        'jsonDecode(response.body) as Map<String, dynamic>);',
      );
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
