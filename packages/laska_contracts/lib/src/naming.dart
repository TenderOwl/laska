/// Naming helpers shared by the generators.
library;

/// Converts a snake_case or kebab-case [value] to PascalCase.
String pascalCase(String value) {
  final parts = _splitWords(value);
  return parts.map(_capitalize).join();
}

/// Converts a snake_case or kebab-case [value] to lowerCamelCase.
///
/// This is also the JSON name protobuf uses for a field.
String camelCase(String value) {
  final parts = _splitWords(value);
  if (parts.isEmpty) {
    return value;
  }
  final head = _capitalize(parts.first).toLowerCase();
  return head + parts.skip(1).map(_capitalize).join();
}

/// Converts a [value] to snake_case.
String snakeCase(String value) =>
    _splitWords(value).map((word) => word.toLowerCase()).join('_');

/// Whether [value] is written in PascalCase.
bool isPascalCase(String value) =>
    value.isNotEmpty && pascalCase(value) == value;

/// Whether [value] is written in snake_case.
bool isSnakeCase(String value) =>
    value.isNotEmpty &&
    RegExp(r'^[a-z][a-z0-9]*(_[a-z0-9]+)*$').hasMatch(value);

/// Whether [value] is written in UPPER_SNAKE_CASE.
bool isUpperSnakeCase(String value) =>
    value.isNotEmpty &&
    RegExp(r'^[A-Z][A-Z0-9]*(_[A-Z0-9]+)*$').hasMatch(value);

/// Converts an UPPER_SNAKE_CASE [value] to lowerCamelCase.
///
/// Used for enum values, which are upper case in a contract but have to be
/// valid Dart enum constant names.
String enumConstantName(String value) {
  final parts = _splitWords(value);
  if (parts.isEmpty) {
    return value;
  }
  final buffer = StringBuffer();
  for (var i = 0; i < parts.length; i++) {
    final word = parts[i].toLowerCase();
    if (i == 0) {
      buffer.write(word);
    } else {
      buffer.write(_capitalize(word));
    }
  }
  return buffer.toString();
}

/// Splits [value] into words on `_`, `-`, `.`, spaces and case boundaries.
List<String> _splitWords(String value) {
  final words = <String>[];
  final buffer = StringBuffer();

  for (var i = 0; i < value.length; i++) {
    final char = value[i];
    if (char == '_' || char == '-' || char == '.' || char == ' ') {
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

String _capitalize(String value) =>
    value.isEmpty ? value : value[0].toUpperCase() + value.substring(1);
