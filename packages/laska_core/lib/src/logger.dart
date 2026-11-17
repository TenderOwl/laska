import 'dart:convert';

import 'config.dart';

/// The severity of a log record.
enum LogLevel {
  /// Verbose information, off by default.
  debug,

  /// Normal operation.
  info,

  /// Something unexpected that the application recovered from.
  warning,

  /// Something that needs attention.
  error,
}

/// A structured logger.
///
/// Every record is written as one JSON object per line, so log aggregators
/// can index the fields instead of parsing a message string. Values of secret
/// configuration keys are redacted.
class Logger {
  /// Creates a logger.
  Logger({
    this.level = LogLevel.info,
    void Function(String line)? sink,
    this.service = 'laska',
    this.version,
    Map<String, Object?> fields = const <String, Object?>{},
  })  : _sink = sink ?? _writeToStdout,
        _fields = Map<String, Object?>.of(fields);

  /// The minimum severity that is written.
  final LogLevel level;

  /// The name of the service, written with every record.
  final String service;

  /// The version of the service, written with every record.
  final String? version;

  /// The fields written with every record.
  final Map<String, Object?> _fields;

  final void Function(String line) _sink;

  /// Returns a logger that writes [fields] with every record.
  ///
  /// The fields of a record win over the fields of the logger, so a caller
  /// can always overwrite a correlation field.
  Logger child(Map<String, Object?> fields) => Logger(
        level: level,
        sink: _sink,
        service: service,
        version: version,
        fields: <String, Object?>{..._fields, ...fields},
      );

  /// Writes a debug record.
  void debug(String message, [Map<String, Object?> fields = const {}]) =>
      log(LogLevel.debug, message, fields);

  /// Writes an informational record.
  void info(String message, [Map<String, Object?> fields = const {}]) =>
      log(LogLevel.info, message, fields);

  /// Writes a warning.
  void warning(String message, [Map<String, Object?> fields = const {}]) =>
      log(LogLevel.warning, message, fields);

  /// Writes an error.
  void error(String message, [Map<String, Object?> fields = const {}]) =>
      log(LogLevel.error, message, fields);

  /// Writes a record of [severity].
  void log(
    LogLevel severity,
    String message, [
    Map<String, Object?> fields = const {},
  ]) {
    if (severity.index < level.index) {
      return;
    }

    final record = <String, Object?>{
      'time': DateTime.now().toUtc().toIso8601String(),
      'level': severity.name,
      'service': service,
      if (version != null) 'version': version,
      'message': message,
      ..._fields.map((key, value) => MapEntry(key, _redact(key, value))),
      ...fields.map((key, value) => MapEntry(key, _redact(key, value))),
    };

    _sink(jsonEncode(record));
  }

  static Object? _redact(String key, Object? value) {
    if (Config.isSecret(key)) {
      return '***';
    }
    if (value is Map<String, Object?>) {
      return value.map((innerKey, innerValue) =>
          MapEntry(innerKey, _redact(innerKey, innerValue)));
    }
    return value;
  }

  static void _writeToStdout(String line) {
    // ignore: avoid_print
    print(line);
  }
}
