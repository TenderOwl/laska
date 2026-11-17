import 'model.dart';

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
/// * enums;
/// * services whose methods may carry a `google.api.http` annotation.
///
/// Constructs that are not part of that subset (`oneof`, `map`, nested
/// messages, nested enums) raise a [ProtoParseException] instead of being
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

  /// Parses the source.
  ProtoFile parse() {
    final package = _guessPackage();
    final messages = <Message>[];
    final enums = <EnumType>[];
    final services = <Service>[];
    final imports = <String>[];

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
          final modifier = _peekIdent();
          if (modifier == 'public' || modifier == 'weak') {
            _readIdent();
          }
          imports.add(_readString());
          _expectChar(';');
        case 'option':
          _skipOption();
        case 'message':
          messages.add(_parseMessage(package));
        case 'enum':
          enums.add(_parseEnum(package));
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

    return ProtoFile(
      path: fileName,
      package: package,
      messages: messages,
      enums: enums,
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

  Message _parseMessage(String package) {
    final doc = _takeDoc();
    _expectIdent('message');
    final name = _readIdent();
    _expectChar('{');

    final fields = <Field>[];
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
          throw _error('Nested messages are not supported yet (in "$name")');
        case 'enum':
          throw _error('Nested enums are not supported yet (in "$name")');
        case 'oneof':
          throw _error('oneof is not supported yet (in "$name")');
        case 'map':
          throw _error('map fields are not supported yet (in "$name")');
        case 'reserved':
          _skipToSemicolon();
        case 'option':
          _skipOption();
        default:
          fields.add(_parseField());
      }
    }

    return Message(
      name: name,
      fields: fields,
      comment: doc,
      package: package,
    );
  }

  Field _parseField() {
    final doc = _takeDoc();
    var repeated = false;
    var optional = false;

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
    );
  }

  EnumType _parseEnum(String package) {
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

    return EnumType(
      name: name,
      values: values,
      comment: doc,
      package: package,
    );
  }

  Service _parseService(String package) {
    final doc = _takeDoc();
    _expectIdent('service');
    final name = _readIdent();
    _expectChar('{');

    final methods = <Method>[];
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
        _skipOption();
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
    );
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
