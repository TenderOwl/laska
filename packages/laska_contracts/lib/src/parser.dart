import 'model.dart';
import 'types.dart';

/// Raised when a contract cannot be parsed.
class ProtoParseException implements Exception {
  /// Creates a parse exception.
  ProtoParseException(this.message, this.fileName, this.line);

  /// Human readable description of the problem.
  final String message;

  /// File the problem was found in.
  final String fileName;

  /// Line the problem was found on.
  final int line;

  @override
  String toString() => '$fileName:$line: $message';
}

/// Parses a `.proto` file into a [ProtoFile].
///
/// The parser understands the subset of proto3 Laska needs:
///
/// * `syntax`, `package` and `import` declarations (imports are recorded but
///   not resolved);
/// * messages with scalar, message, enum and repeated fields;
/// * `map` fields;
/// * groups of a `oneof`;
/// * messages and enums declared inside a message;
/// * enums;
/// * services whose methods may carry a `google.api.http` annotation.
///
/// The types that are written without a qualifier are resolved the way
/// protobuf resolves them: the scope of the message is searched first, then
/// the scopes it is declared in, and the types of the file are known.
///
/// Constructs that are not part of that subset (`proto2`, the well-known
/// types, the extensions) raise a [ProtoParseException] instead of being
/// silently ignored.
class ProtoParser {
  /// Creates a parser for [source].
  ProtoParser(this.source, {this.fileName = '<memory>'});

  /// The contract source.
  final String source;

  /// Name of the file, used in error messages.
  final String fileName;

  int _pos = 0;
  int _line = 1;
  int _lineStart = 0;
  final List<String> _doc = <String>[];

  /// The messages of the file, nested ones included.
  final List<Message> _messages = <Message>[];

  /// The enums of the file, nested ones included.
  final List<EnumType> _enums = <EnumType>[];

  /// Parses the source.
  ProtoFile parse() {
    final package = _guessPackage();
    final services = <Service>[];
    final imports = <ProtoImport>[];

    while (true) {
      _skipTrivia();
      if (_pos >= source.length) {
        break;
      }
      final word = _peekIdent() ?? '';
      switch (word) {
        case 'syntax':
          _expectIdent('syntax');
          _expectChar('=');
          final value = _readString();
          if (value != 'proto3') {
            throw _error('Only proto3 contracts are supported, got "$value"');
          }
          _expectChar(';');
        case 'package':
          _expectIdent('package');
          _readTypeName();
          _expectChar(';');
        case 'import':
          _expectIdent('import');
          var isPublic = false;
          final modifier = _peekIdent();
          if (modifier == 'public' || modifier == 'weak') {
            _readIdent();
            isPublic = modifier == 'public';
          }
          imports.add(ProtoImport(_readString(), isPublic: isPublic));
          _expectChar(';');
        case 'option':
          _skipOption();
        case 'message':
          _flatten(_parseMessage(package, ''));
        case 'enum':
          _parseEnum(package, '');
        case 'service':
          services.add(_parseService(package));
        case ';':
          _pos++;
        default:
          throw _error(
            word.isEmpty
                ? 'Unexpected character "${source[_pos]}"'
                : 'Unexpected top level declaration "$word"',
          );
      }
    }

    _resolveTypes(package, services);

    return ProtoFile(
      path: fileName,
      package: package,
      messages: _messages,
      enums: _enums,
      services: services,
      imports: imports,
    );
  }

  String _guessPackage() {
    final match = RegExp(
      r'^\s*package\s+([A-Za-z_][A-Za-z0-9_.]*)\s*;',
      multiLine: true,
    ).firstMatch(source);
    return match?.group(1) ?? '';
  }

  /// Parses a message and the declarations it holds.
  ///
  /// The [scope] is the scope the message is declared in, e.g. `Order` for a
  /// message declared inside the message `Order`.
  _Parsed _parseMessage(String package, String scope) {
    final doc = _takeDoc();
    _expectIdent('message');
    final name = _readIdent();
    _expectChar('{');

    final childScope = scope.isEmpty ? name : '$scope.$name';
    final fields = <Field>[];
    final oneofs = <Oneof>[];
    final nested = <_Parsed>[];

    while (true) {
      _skipTrivia();
      if (_pos >= source.length) {
        throw _error('Unterminated message "$name"');
      }
      if (source[_pos] == '}') {
        _pos++;
        break;
      }
      if (source[_pos] == ';') {
        _pos++;
        continue;
      }

      final word = _peekIdent() ?? '';
      switch (word) {
        case 'message':
          nested.add(_parseMessage(package, childScope));
        case 'enum':
          _parseEnum(package, childScope);
        case 'oneof':
          oneofs.add(_parseOneof(package));
        case 'map':
          fields.add(_parseMapField());
        case 'reserved':
          _skipToSemicolon();
        case 'option':
          _takeDoc();
          _skipOption();
        case 'extend':
          throw _error('Extensions are not supported yet (in "$name")');
        default:
          fields.add(_parseField());
      }
    }

    return _Parsed(
      Message(
        name: name,
        fields: fields,
        oneofs: oneofs,
        comment: doc,
        package: package,
        scope: scope,
      ),
      nested,
    );
  }

  /// Adds a parsed message and the messages it holds to the list of the file.
  ///
  /// A message comes before the messages it holds, so the generated code reads
  /// from the outside in.
  void _flatten(_Parsed parsed) {
    _messages.add(parsed.message);
    for (final child in parsed.nested) {
      _flatten(child);
    }
  }

  /// Parses a group of a `oneof`.
  Oneof _parseOneof(String package) {
    final doc = _takeDoc();
    _expectIdent('oneof');
    final name = _readIdent();
    _expectChar('{');

    final fields = <Field>[];
    while (true) {
      _skipTrivia();
      if (_pos >= source.length) {
        throw _error('Unterminated oneof "$name"');
      }
      if (source[_pos] == '}') {
        _pos++;
        break;
      }
      if (source[_pos] == ';') {
        _pos++;
        continue;
      }
      if (_peekIdent() == 'option') {
        _takeDoc();
        _skipOption();
        continue;
      }

      fields.add(_parseField(oneof: name));
    }

    return Oneof(name: name, fields: fields, comment: doc);
  }

  /// Parses a field of a message.
  Field _parseField({String? oneof}) {
    final doc = _takeDoc();
    var repeated = false;
    var optional = oneof != null;

    final label = _peekIdent();
    if (label == 'repeated') {
      repeated = true;
      _expectIdent('repeated');
    } else if (label == 'optional') {
      optional = true;
      _expectIdent('optional');
    } else if (label == 'required') {
      _expectIdent('required');
    }

    final type = _readTypeName();
    final name = _readIdent();
    _expectChar('=');
    final number = _readInt();
    _skipTrivia();
    if (_pos < source.length && source[_pos] == '[') {
      _skipBracketBlock();
    }
    _expectChar(';');

    return Field(
      name: name,
      number: number,
      type: type,
      repeated: repeated,
      optional: optional,
      comment: doc,
      oneof: oneof,
    );
  }

  /// Parses a field of a map, e.g. `map<string, int32> quantities = 3;`.
  Field _parseMapField() {
    final doc = _takeDoc();
    _expectIdent('map');
    _expectChar('<');
    final keyType = _readTypeName();
    _expectChar(',');
    final valueType = _readTypeName();
    _expectChar('>');

    final name = _readIdent();
    _expectChar('=');
    final number = _readInt();
    _skipTrivia();
    if (_pos < source.length && source[_pos] == '[') {
      _skipBracketBlock();
    }
    _expectChar(';');

    return Field(
      name: name,
      number: number,
      type: 'map',
      mapKeyType: keyType,
      mapValueType: valueType,
      comment: doc,
    );
  }

  EnumType _parseEnum(String package, String scope) {
    final doc = _takeDoc();
    _expectIdent('enum');
    final name = _readIdent();
    _expectChar('{');

    final values = <EnumValue>[];
    while (true) {
      _skipTrivia();
      if (_pos >= source.length) {
        throw _error('Unterminated enum "$name"');
      }
      if (source[_pos] == '}') {
        _pos++;
        break;
      }
      if (source[_pos] == ';') {
        _pos++;
        continue;
      }

      final word = _peekIdent() ?? '';
      if (word == 'option') {
        _takeDoc();
        _skipOption();
        continue;
      }
      if (word == 'reserved') {
        _skipToSemicolon();
        continue;
      }

      final valueDoc = _takeDoc();
      final valueName = _readIdent();
      _expectChar('=');
      final valueNumber = _readInt();
      _skipTrivia();
      if (_pos < source.length && source[_pos] == '[') {
        _skipBracketBlock();
      }
      _expectChar(';');
      values.add(
        EnumValue(
          name: valueName,
          number: valueNumber,
          comment: valueDoc,
        ),
      );
    }

    final enumType = EnumType(
      name: name,
      values: values,
      comment: doc,
      package: package,
      scope: scope,
    );
    _enums.add(enumType);
    return enumType;
  }

  /// Resolves the types that are written without a qualifier.
  ///
  /// The scope of the message is searched first, then the scopes the message
  /// is declared in, and the types of the file are known. A type that is not
  /// found is left as it was written: it may belong to another file.
  void _resolveTypes(String package, List<Service> services) {
    final local = <String, String>{};
    for (final message in _messages) {
      final relative = message.scope.isEmpty
          ? message.name
          : '${message.scope}.${message.name}';
      local[relative] = message.fullName;
    }
    for (final enumType in _enums) {
      final relative = enumType.scope.isEmpty
          ? enumType.name
          : '${enumType.scope}.${enumType.name}';
      local[relative] = enumType.fullName;
    }

    String qualify(String reference, List<String> scopes) {
      if (reference.startsWith('.')) {
        return reference.substring(1);
      }
      final known = local[reference];
      if (known != null) {
        return known;
      }
      for (final scope in scopes) {
        final resolved = local['$scope.$reference'];
        if (resolved != null) {
          return resolved;
        }
      }
      return reference;
    }

    for (final message in _messages) {
      final scopes = _scopeChain(message);
      for (final field in message.allFields) {
        if (field.isMap) {
          field.mapValueType = qualify(field.mapValueType!, scopes);
        } else if (!scalarTypes.containsKey(field.type)) {
          field.type = qualify(field.type, scopes);
        }
      }
    }

    for (final service in services) {
      for (final method in service.methods) {
        method.requestType = qualify(method.requestType, const <String>[]);
        method.responseType = qualify(method.responseType, const <String>[]);
      }
    }
  }

  /// The scopes the types of a message may be declared in.
  ///
  /// The scope of the message comes first — the types declared inside it are
  /// seen by its fields — and then the scopes the message is declared in.
  static List<String> _scopeChain(Message message) {
    final own = message.scope.isEmpty
        ? message.name
        : '${message.scope}.${message.name}';
    final parts = message.scope.isEmpty ? <String>[] : message.scope.split('.');

    return <String>[
      own,
      for (var i = parts.length; i > 0; i--) parts.sublist(0, i).join('.'),
    ];
  }

  Service _parseService(String package) {
    final doc = _takeDoc();
    _expectIdent('service');
    final name = _readIdent();
    _expectChar('{');

    final methods = <Method>[];
    MethodPolicy? servicePolicy;
    while (true) {
      _skipTrivia();
      if (_pos >= source.length) {
        throw _error('Unterminated service "$name"');
      }
      if (source[_pos] == '}') {
        _pos++;
        break;
      }
      if (source[_pos] == ';') {
        _pos++;
        continue;
      }

      final word = _peekIdent() ?? '';
      if (word == 'option') {
        _takeDoc();
        _expectIdent('option');
        final optionName = _readOptionName();
        _expectChar('=');
        if (optionName == '(laska.policy)') {
          servicePolicy = _parsePolicy();
        } else {
          _skipOptionValue();
        }
        _expectChar(';');
        continue;
      }
      if (word != 'rpc') {
        throw _error('Unexpected declaration "$word" in service "$name"');
      }
      methods.add(_parseMethod());
    }

    return Service(
      name: name,
      methods: methods,
      comment: doc,
      package: package,
      policy: servicePolicy,
    );
  }

  Method _parseMethod() {
    final doc = _takeDoc();
    _expectIdent('rpc');
    final name = _readIdent();

    _expectChar('(');
    final requestType = _readTypeName();
    _expectChar(')');

    _expectIdent('returns');
    _expectChar('(');
    final responseType = _readTypeName();
    _expectChar(')');

    final rules = <HttpRule>[];
    MethodPolicy? policy;
    _skipTrivia();
    if (_pos < source.length && source[_pos] == '{') {
      _pos++;
      while (true) {
        _skipTrivia();
        if (_pos >= source.length) {
          throw _error('Unterminated body of method "$name"');
        }
        if (source[_pos] == '}') {
          _pos++;
          break;
        }
        if (source[_pos] == ';') {
          _pos++;
          continue;
        }
        if (_peekIdent() != 'option') {
          throw _error('Unexpected declaration in body of method "$name"');
        }
        _expectIdent('option');
        final optionName = _readOptionName();
        _expectChar('=');
        if (optionName == '(google.api.http)') {
          rules.addAll(_parseHttpRules());
        } else if (optionName == '(laska.policy)') {
          policy = _parsePolicy();
        } else {
          _skipOptionValue();
        }
        _expectChar(';');
      }
    } else {
      _expectChar(';');
    }

    return Method(
      name: name,
      requestType: requestType,
      responseType: responseType,
      httpRules: rules,
      comment: doc,
      policy: policy,
    );
  }

  /// Parses the `laska.policy` annotation of a method or of a service.
  ///
  /// The annotation holds the keys of the policy of the call:
  ///
  /// ```
  /// option (laska.policy) = {
  ///   timeout_ms: 2000
  ///   max_attempts: 3
  ///   backoff_ms: 100
  ///   max_backoff_ms: 2000
  ///   jitter: true
  ///   idempotent: true
  /// };
  /// ```
  MethodPolicy _parsePolicy() {
    _expectChar('{');
    Duration? timeout;
    int? maxAttempts;
    Duration? backoff;
    Duration? maxBackoff;
    bool? jitter;
    bool? idempotent;

    while (true) {
      _skipTrivia();
      if (_pos >= source.length) {
        throw _error('Unterminated laska.policy annotation');
      }
      if (source[_pos] == '}') {
        _pos++;
        break;
      }
      if (source[_pos] == ';') {
        _pos++;
        continue;
      }

      final key = _readIdent();
      _expectChar(':');
      final value = _readPolicyValue();

      switch (key) {
        case 'timeout_ms':
          timeout = Duration(milliseconds: _asInt(value, key));
        case 'max_attempts':
          maxAttempts = _asInt(value, key);
        case 'backoff_ms':
          backoff = Duration(milliseconds: _asInt(value, key));
        case 'max_backoff_ms':
          maxBackoff = Duration(milliseconds: _asInt(value, key));
        case 'jitter':
          jitter = _asBool(value, key);
        case 'idempotent':
          idempotent = _asBool(value, key);
        default:
          throw _error('Unknown key "$key" in the laska.policy annotation');
      }
      _skipOptionalComma();
    }

    return MethodPolicy(
      timeout: timeout,
      maxAttempts: maxAttempts,
      backoff: backoff,
      maxBackoff: maxBackoff,
      jitter: jitter,
      idempotent: idempotent,
    );
  }

  /// Reads the value of a key of the `laska.policy` annotation.
  Object _readPolicyValue() {
    _skipTrivia();
    if (_pos >= source.length) {
      throw _error('Expected a value in the laska.policy annotation');
    }

    final char = source[_pos];
    if (char == '-' || _isDigit(char)) {
      return _readInt();
    }

    final word = _readIdent();
    if (word == 'true') {
      return true;
    }
    if (word == 'false') {
      return false;
    }
    return word;
  }

  int _asInt(Object value, String key) {
    if (value is int) {
      return value;
    }
    throw _error(
        'The key "$key" of the laska.policy annotation needs a number');
  }

  bool _asBool(Object value, String key) {
    if (value is bool) {
      return value;
    }
    throw _error('The key "$key" of the laska.policy annotation needs true or '
        'false');
  }

  List<HttpRule> _parseHttpRules() {
    _expectChar('{');
    final rules = <HttpRule>[];
    HttpRule? current;

    while (true) {
      _skipTrivia();
      if (_pos >= source.length) {
        throw _error('Unterminated google.api.http annotation');
      }
      if (source[_pos] == '}') {
        _pos++;
        break;
      }

      final key = _readIdent();
      _skipTrivia();
      if (_pos < source.length && source[_pos] == '{') {
        rules.addAll(_parseHttpRules());
        _skipOptionalComma();
        continue;
      }

      _expectChar(':');
      final value = _readString();
      if (key == 'body') {
        current?.body = value;
      } else {
        current = HttpRule(method: key.toUpperCase(), path: value);
        rules.add(current);
      }
      _skipOptionalComma();
    }

    return rules;
  }

  void _skipOptionalComma() {
    _skipTrivia();
    if (_pos < source.length && source[_pos] == ',') {
      _pos++;
    }
  }

  void _skipOption() {
    _expectIdent('option');
    _readOptionName();
    _expectChar('=');
    _skipOptionValue();
    _expectChar(';');
  }

  String _readOptionName() {
    _skipTrivia();
    if (_pos < source.length && source[_pos] == '(') {
      final end = source.indexOf(')', _pos);
      if (end == -1) {
        throw _error('Unterminated option name');
      }
      final name = source.substring(_pos, end + 1);
      _pos = end + 1;
      return name;
    }
    return _readTypeName();
  }

  void _skipOptionValue() {
    _skipTrivia();
    if (_pos >= source.length) {
      throw _error('Expected an option value');
    }
    final char = source[_pos];
    if (char == '{') {
      _skipBlock();
      return;
    }
    if (char == '"' || char == "'") {
      _readString();
      return;
    }
    final start = _pos;
    while (_pos < source.length && _isValueChar(source[_pos])) {
      _pos++;
    }
    if (start == _pos) {
      throw _error('Expected an option value');
    }
  }

  void _skipBlock() {
    var depth = 0;
    while (_pos < source.length) {
      final char = source[_pos];
      if (char == '"' || char == "'") {
        _readString();
        continue;
      }
      if (char == '{') {
        depth++;
      } else if (char == '}') {
        depth--;
        _pos++;
        if (depth == 0) {
          return;
        }
        continue;
      } else if (char == '\n') {
        _line++;
      }
      _pos++;
    }
    throw _error('Unterminated block');
  }

  void _skipBracketBlock() {
    var depth = 0;
    while (_pos < source.length) {
      final char = source[_pos];
      if (char == '"' || char == "'") {
        _readString();
        continue;
      }
      if (char == '[' || char == '{' || char == '(') {
        depth++;
      } else if (char == ']' || char == '}' || char == ')') {
        depth--;
        _pos++;
        if (depth == 0) {
          return;
        }
        continue;
      } else if (char == '\n') {
        _line++;
      }
      _pos++;
    }
    throw _error('Unterminated option block');
  }

  void _skipToSemicolon() {
    var depth = 0;
    while (_pos < source.length) {
      final char = source[_pos];
      if (char == '"' || char == "'") {
        _readString();
        continue;
      }
      if (char == '{' || char == '[' || char == '(') {
        depth++;
      } else if (char == '}' || char == ']' || char == ')') {
        depth--;
      } else if (char == ';' && depth == 0) {
        _pos++;
        return;
      } else if (char == '\n') {
        _line++;
      }
      _pos++;
    }
    throw _error('Unterminated declaration');
  }

  void _skipTrivia() {
    while (_pos < source.length) {
      final char = source[_pos];
      if (char == '\n') {
        _line++;
        _pos++;
        _lineStart = _pos;
        continue;
      }
      if (char == ' ' || char == '\t' || char == '\r') {
        _pos++;
        continue;
      }
      if (char == '/' && _pos + 1 < source.length) {
        final next = source[_pos + 1];
        if (next == '/') {
          final end = source.indexOf('\n', _pos);
          final stop = end == -1 ? source.length : end;
          final text = source.substring(_pos + 2, stop).trim();
          final isOwnLine = source.substring(_lineStart, _pos).trim().isEmpty;
          if (text.isNotEmpty && isOwnLine) {
            _doc.add(text);
          }
          _pos = stop;
          continue;
        }
        if (next == '*') {
          final end = source.indexOf('*/', _pos + 2);
          _pos = end == -1 ? source.length : end + 2;
          continue;
        }
      }
      return;
    }
  }

  String? _peekIdent() {
    _skipTrivia();
    if (_pos >= source.length || !_isIdentStart(source[_pos])) {
      return null;
    }
    final start = _pos;
    var end = _pos;
    while (end < source.length && _isIdentChar(source[end])) {
      end++;
    }
    return source.substring(start, end);
  }

  String _readIdent() {
    _skipTrivia();
    final start = _pos;
    while (_pos < source.length && _isIdentChar(source[_pos])) {
      _pos++;
    }
    if (start == _pos) {
      throw _error('Expected an identifier');
    }
    return source.substring(start, _pos);
  }

  String _readTypeName() {
    final parts = <String>[_readIdent()];
    while (true) {
      _skipTrivia();
      if (_pos < source.length && source[_pos] == '.') {
        _pos++;
        parts.add(_readIdent());
        continue;
      }
      break;
    }
    return parts.join('.');
  }

  String _readString() {
    _skipTrivia();
    if (_pos >= source.length) {
      throw _error('Expected a string');
    }
    final quote = source[_pos];
    if (quote != '"' && quote != "'") {
      throw _error('Expected a string');
    }
    _pos++;

    final buffer = StringBuffer();
    while (_pos < source.length && source[_pos] != quote) {
      final char = source[_pos];
      if (char == '\\' && _pos + 1 < source.length) {
        _pos++;
        final escaped = source[_pos];
        buffer.write(
          switch (escaped) {
            'n' => '\n',
            't' => '\t',
            'r' => '\r',
            _ => escaped,
          },
        );
      } else {
        if (char == '\n') {
          _line++;
        }
        buffer.write(char);
      }
      _pos++;
    }

    if (_pos >= source.length) {
      throw _error('Unterminated string');
    }
    _pos++;
    return buffer.toString();
  }

  int _readInt() {
    _skipTrivia();
    final start = _pos;
    if (_pos < source.length && (source[_pos] == '-' || source[_pos] == '+')) {
      _pos++;
    }
    while (_pos < source.length && _isDigit(source[_pos])) {
      _pos++;
    }
    if (start == _pos) {
      throw _error('Expected a number');
    }
    return int.parse(source.substring(start, _pos));
  }

  void _expectIdent(String expected) {
    final ident = _readIdent();
    if (ident != expected) {
      throw _error('Expected "$expected", got "$ident"');
    }
  }

  void _expectChar(String expected) {
    _skipTrivia();
    if (_pos >= source.length || source[_pos] != expected) {
      throw _error('Expected "$expected"');
    }
    _pos++;
  }

  String? _takeDoc() {
    if (_doc.isEmpty) {
      return null;
    }
    final text = _doc.join('\n');
    _doc.clear();
    return text;
  }

  ProtoParseException _error(String message) =>
      ProtoParseException(message, fileName, _line);

  static bool _isIdentStart(String char) {
    final code = char.codeUnitAt(0);
    return (code >= 65 && code <= 90) ||
        (code >= 97 && code <= 122) ||
        char == '_';
  }

  static bool _isIdentChar(String char) =>
      _isIdentStart(char) || _isDigit(char);

  static bool _isDigit(String char) {
    final code = char.codeUnitAt(0);
    return code >= 48 && code <= 57;
  }

  static bool _isValueChar(String char) =>
      _isIdentChar(char) || char == '.' || char == '-' || char == '+';
}

/// A parsed message and the messages it holds.
class _Parsed {
  _Parsed(this.message, this.nested);

  /// The message itself.
  final Message message;

  /// The messages declared inside the message.
  final List<_Parsed> nested;
}
