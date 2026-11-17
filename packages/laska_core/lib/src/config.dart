import 'dart:io';

/// A configuration value that must never end up in a log line.
///
/// The [toString] of a secret is redacted, so a secret cannot leak by
/// accident through string interpolation.
class Secret {
  /// Wraps [value] as a secret.
  const Secret(this.value);

  /// The plain value. Read it explicitly, never through [toString].
  final String value;

  @override
  String toString() => '***';
}

/// Reads configuration values from the environment.
///
/// Values are looked up in the process environment first and in the `.env`
/// file second, so an explicit environment variable always wins over the file.
class Config {
  Config._();

  static final Map<String, String> _file = <String, String>{};
  static final Set<String> _secrets = <String>{
    'password',
    'secret',
    'token',
    'api_key',
    'apikey',
    'authorization',
    'private_key',
  };

  /// Loads the values of a `.env` file.
  ///
  /// Missing files are ignored, so the same code works in production where the
  /// values come from the environment.
  static void loadDotEnv([String path = '.env']) {
    final file = File(path);
    if (!file.existsSync()) {
      return;
    }
    for (final line in file.readAsLinesSync()) {
      final trimmed = line.trim();
      if (trimmed.isEmpty || trimmed.startsWith('#')) {
        continue;
      }
      final separator = trimmed.indexOf('=');
      if (separator == -1) {
        continue;
      }
      final key = trimmed.substring(0, separator).trim();
      var value = trimmed.substring(separator + 1).trim();
      if (value.length >= 2 &&
          ((value.startsWith('"') && value.endsWith('"')) ||
              (value.startsWith("'") && value.endsWith("'")))) {
        value = value.substring(1, value.length - 1);
      }
      _file[key] = value;
    }
  }

  /// The raw value of [key], or `null` when it is not set.
  static String? lookup(String key) {
    final fromEnvironment = Platform.environment[key];
    if (fromEnvironment != null) {
      return fromEnvironment;
    }
    return _file[key];
  }

  /// The value of [key] as a string.
  static String string(String key, {String defaultValue = ''}) =>
      lookup(key) ?? defaultValue;

  /// The value of [key] as an integer.
  static int integer(String key, {int defaultValue = 0}) {
    final value = lookup(key);
    if (value == null) {
      return defaultValue;
    }
    return int.tryParse(value) ?? defaultValue;
  }

  /// The value of [key] as a floating point number.
  static double number(String key, {double defaultValue = 0}) {
    final value = lookup(key);
    if (value == null) {
      return defaultValue;
    }
    return double.tryParse(value) ?? defaultValue;
  }

  /// The value of [key] as a boolean.
  static bool boolean(String key, {bool defaultValue = false}) {
    final value = lookup(key)?.toLowerCase();
    if (value == null) {
      return defaultValue;
    }
    return value == 'true' || value == '1' || value == 'yes';
  }

  /// The value of [key] as a list of comma separated items.
  static List<String> list(String key, {List<String> defaultValue = const []}) {
    final value = lookup(key);
    if (value == null || value.isEmpty) {
      return defaultValue;
    }
    return value.split(',').map((item) => item.trim()).toList();
  }

  /// The value of [key] as a secret.
  static Secret secret(String key, {String defaultValue = ''}) {
    redact(key);
    return Secret(lookup(key) ?? defaultValue);
  }

  /// Marks the value of [key] as secret, so it is redacted in logs.
  static void redact(String key) {
    _secrets.add(key.toLowerCase());
  }

  /// Whether the value of [key] is redacted in logs.
  static bool isSecret(String key) => _secrets.contains(key.toLowerCase());

  /// Every known value, with the secrets redacted.
  static Map<String, String> get redacted {
    final keys = <String>{...Platform.environment.keys, ..._file.keys};
    return <String, String>{
      for (final key in keys) key: isSecret(key) ? '***' : (lookup(key) ?? ''),
    };
  }

  /// Clears the values loaded from a `.env` file. Used by tests.
  static void reset() {
    _file.clear();
    _secrets
      ..clear()
      ..addAll(const <String>{
        'password',
        'secret',
        'token',
        'api_key',
        'apikey',
        'authorization',
        'private_key',
      });
  }
}
