import 'errors.dart';

/// Parses an integer coming from a path or query parameter.
///
/// Throws [HttpException] with status 400 when [raw] is not an integer.
int parseIntValue(String raw, String name) {
  final value = int.tryParse(raw);
  if (value == null) {
    throw HttpException(400, 'Value of "$name" must be an integer');
  }
  return value;
}

/// Parses a floating point number coming from a path or query parameter.
///
/// Throws [HttpException] with status 400 when [raw] is not a number.
double parseDoubleValue(String raw, String name) {
  final value = double.tryParse(raw);
  if (value == null) {
    throw HttpException(400, 'Value of "$name" must be a number');
  }
  return value;
}

/// Parses a boolean coming from a path or query parameter.
///
/// Accepts `true`, `false`, `1` and `0`. Throws [HttpException] with status 400
/// for anything else.
bool parseBoolValue(String raw, String name) {
  switch (raw.toLowerCase()) {
    case 'true':
    case '1':
      return true;
    case 'false':
    case '0':
      return false;
    default:
      throw HttpException(400, 'Value of "$name" must be a boolean');
  }
}
