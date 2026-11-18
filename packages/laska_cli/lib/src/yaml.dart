/// A minimal parser of the YAML subset the manifests of Laska use.
///
/// The manifests are written by Laska itself and by the user, so the parser
/// covers what a manifest needs and nothing more: nested maps, lists of
/// scalars, lists of maps, inline lists and comments. Anchors, aliases, tags,
/// multi-line scalars and other parts of YAML are not supported — a manifest
/// that uses them is reported as an error instead of being read wrongly.
library;

/// Raised when a YAML document cannot be read.
class YamlException implements Exception {
  /// Creates an exception for the line [line] with the [message].
  YamlException(this.message, {this.line});

  /// Human readable description of the problem.
  final String message;

  /// The number of the line the problem was found on, when it is known.
  final int? line;

  @override
  String toString() => line == null
      ? 'YamlException: $message'
      : 'YamlException: line $line: $message';
}

/// Parses [source] into maps, lists and strings.
///
/// The result is a `Map<String, Object?>` for a document, a `List<Object?>` for
/// a sequence and a `String` for a scalar.
Object? parseYaml(String source) => _YamlParser(source).parse();

/// One line of the document.
class _Line {
  const _Line(this.number, this.indent, this.content);

  /// The number of the line in the document, starting at 1.
  final int number;

  /// The number of the spaces the line is indented with.
  final int indent;

  /// The content of the line, without the indentation and the comment.
  final String content;
}

/// The parser of a YAML document.
class _YamlParser {
  _YamlParser(String source) : _lines = _tokenize(source);

  final List<_Line> _lines;
  int _index = 0;

  /// Parses the whole document.
  Object? parse() {
    if (_lines.isEmpty) {
      return null;
    }
    final result = _parseBlock(_lines.first.indent);
    if (_index < _lines.length) {
      throw YamlException(
        'unexpected content',
        line: _lines[_index].number,
      );
    }
    return result;
  }

  /// Parses the block that starts at the current line.
  Object? _parseBlock(int indent) {
    if (_index >= _lines.length) {
      return null;
    }
    if (_lines[_index].content.startsWith('- ')) {
      return _parseList(indent);
    }
    return _parseMap(indent);
  }

  /// Parses a map of the lines indented with [indent].
  Map<String, Object?> _parseMap(int indent) {
    final map = <String, Object?>{};

    while (_index < _lines.length) {
      final line = _lines[_index];
      if (line.indent < indent) {
        break;
      }
      if (line.indent > indent) {
        throw YamlException('unexpected indentation', line: line.number);
      }
      if (line.content.startsWith('- ')) {
        break;
      }

      final separator = _separator(line.content);
      if (separator == -1) {
        throw YamlException('expected "key: value"', line: line.number);
      }

      final key = line.content.substring(0, separator).trim();
      if (key.isEmpty) {
        throw YamlException('expected a key', line: line.number);
      }

      final rest = line.content.substring(separator + 1).trim();
      _index++;

      if (rest.isEmpty) {
        map[key] = _parseNested(indent, line);
      } else {
        map[key] = _parseScalar(rest, line);
      }
    }

    return map;
  }

  /// Parses the value that follows a key with an empty value.
  Object? _parseNested(int indent, _Line line) {
    if (_index >= _lines.length) {
      return null;
    }
    final next = _lines[_index];
    if (next.indent <= indent) {
      return null;
    }
    return _parseBlock(next.indent);
  }

  /// Parses a list of the lines indented with [indent].
  List<Object?> _parseList(int indent) {
    final list = <Object?>[];

    while (_index < _lines.length) {
      final line = _lines[_index];
      if (line.indent < indent) {
        break;
      }
      if (line.indent > indent) {
        throw YamlException('unexpected indentation', line: line.number);
      }
      if (!line.content.startsWith('- ')) {
        break;
      }

      final item = line.content.substring(2).trim();
      _index++;

      if (item.isEmpty) {
        throw YamlException('expected a value after "-"', line: line.number);
      }

      if (_isMapItem(item)) {
        list.add(_parseMapItem(line, item));
      } else {
        list.add(_parseScalar(item, line));
      }
    }

    return list;
  }

  /// Parses the map of a list item that starts with its first key.
  Map<String, Object?> _parseMapItem(_Line line, String item) {
    final separator = _separator(item);
    final key = item.substring(0, separator).trim();
    final rest = item.substring(separator + 1).trim();

    // The first key of the item is on the line of the dash, the other keys
    // are on the lines that follow it. The map is read at the indentation of
    // those lines, so a manifest may indent them the way it likes.
    var itemIndent = line.indent + 2;
    if (_index < _lines.length && _lines[_index].indent > line.indent) {
      itemIndent = _lines[_index].indent;
    }

    final map = <String, Object?>{};
    if (rest.isEmpty) {
      map[key] = _parseNested(itemIndent, line);
    } else {
      map[key] = _parseScalar(rest, line);
    }

    while (_index < _lines.length) {
      final next = _lines[_index];
      if (next.indent < itemIndent) {
        break;
      }
      if (next.indent > itemIndent) {
        throw YamlException('unexpected indentation', line: next.number);
      }
      if (next.content.startsWith('- ')) {
        break;
      }
      map.addAll(_parseMap(itemIndent));
      break;
    }

    return map;
  }

  /// Parses a scalar or an inline list.
  Object? _parseScalar(String value, _Line line) {
    if (value.startsWith('[') && value.endsWith(']')) {
      final inner = value.substring(1, value.length - 1).trim();
      if (inner.isEmpty) {
        return <String>[];
      }
      return inner
          .split(',')
          .map((item) => _unquote(item.trim()))
          .toList(growable: false);
    }

    if (value.startsWith('"') || value.startsWith("'")) {
      return _unquote(value);
    }

    if (value == '{}' || value == '[]') {
      return null;
    }

    if (value.startsWith('&') ||
        value.startsWith('*') ||
        value.startsWith('!')) {
      throw YamlException(
        'the anchors, the aliases and the tags are not supported',
        line: line.number,
      );
    }

    return _unquote(value);
  }

  /// Whether the item of a list starts a map.
  bool _isMapItem(String item) {
    if (item.startsWith('"') || item.startsWith("'")) {
      return false;
    }
    return _separator(item) != -1;
  }

  /// The position of the colon that separates a key from its value.
  ///
  /// Returns `-1` when the text has no separator.
  int _separator(String text) {
    var quote = '';
    for (var index = 0; index < text.length; index++) {
      final character = text[index];
      if (quote.isNotEmpty) {
        if (character == quote) {
          quote = '';
        }
        continue;
      }
      if (character == '"' || character == "'") {
        quote = character;
        continue;
      }
      if (character == ':' &&
          (index + 1 == text.length || text[index + 1] == ' ')) {
        return index;
      }
    }
    return -1;
  }

  /// Removes the quotes of a value.
  String _unquote(String value) {
    if (value.length >= 2 &&
        ((value.startsWith('"') && value.endsWith('"')) ||
            (value.startsWith("'") && value.endsWith("'")))) {
      return value.substring(1, value.length - 1);
    }
    return value;
  }

  /// Splits the source into the lines of the document.
  static List<_Line> _tokenize(String source) {
    final lines = <_Line>[];
    final raw = source.split('\n');

    for (var index = 0; index < raw.length; index++) {
      final line = raw[index].replaceAll('\t', '  ');
      final trimmed = line.trim();
      if (trimmed.isEmpty || trimmed.startsWith('#')) {
        continue;
      }

      final withoutComment = _stripComment(line);
      if (withoutComment.trim().isEmpty) {
        continue;
      }

      final indent = withoutComment.length - withoutComment.trimLeft().length;
      lines.add(_Line(index + 1, indent, withoutComment.trimRight().trim()));
    }

    return lines;
  }

  /// Removes the comment of a line.
  static String _stripComment(String line) {
    var quote = '';
    for (var index = 0; index < line.length; index++) {
      final character = line[index];
      if (quote.isNotEmpty) {
        if (character == quote) {
          quote = '';
        }
        continue;
      }
      if (character == '"' || character == "'") {
        quote = character;
        continue;
      }
      if (character == '#' && index > 0 && line[index - 1] == ' ') {
        return line.substring(0, index);
      }
    }
    return line;
  }
}
