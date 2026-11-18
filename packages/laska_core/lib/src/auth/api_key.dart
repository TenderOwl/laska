/// The API keys of the clients of a service.
///
/// A service that is called by another service — or by a machine — often
/// answers with an API key instead of a token. The key is a secret that the
/// client sends in a header, and the service only keeps its hash, so a leak
/// of the database of the service does not leak the keys of the clients.
library;

import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';

/// A key of a client.
class ApiKey {
  /// Creates a key.
  ///
  /// The [hash] is the hash of the key, not the key itself.
  const ApiKey({
    required this.id,
    required this.hash,
    this.name,
    this.scopes = const <String>[],
  });

  /// The identifier of the key.
  final String id;

  /// The name of the client the key belongs to.
  final String? name;

  /// The hash of the key.
  final String hash;

  /// What the key may do.
  final List<String> scopes;

  /// Whether the key may do [scope].
  bool allows(String scope) => scopes.isEmpty || scopes.contains(scope);
}

/// The guard that checks the API keys of the clients.
class ApiKeyGuard {
  /// Creates a guard for the [keys].
  ApiKeyGuard(List<ApiKey> keys)
      : _keys = <String, ApiKey>{
          for (final key in keys) key.hash: key,
        };

  /// Creates a guard for the plain [keys].
  ///
  /// The keys are hashed, so the guard never holds them.
  factory ApiKeyGuard.fromPlain(List<String> keys) => ApiKeyGuard(
        keys
            .map(
              (key) => ApiKey(
                id: hashApiKey(key).substring(0, 12),
                hash: hashApiKey(key),
              ),
            )
            .toList(),
      );

  final Map<String, ApiKey> _keys;

  /// The number of the keys the guard knows.
  int get length => _keys.length;

  /// Checks the key the client sent.
  ///
  /// Returns `null` when the key is unknown. The comparison takes the same
  /// time whatever the key is, so the answer does not tell the attacker how
  /// much of the key was right.
  ApiKey? verify(String? presented) {
    if (presented == null || presented.isEmpty) {
      return null;
    }

    final hash = hashApiKey(presented);
    ApiKey? found;
    var difference = 0;

    _keys.forEach((keyHash, key) {
      difference |= _compare(keyHash, hash);
      if (_compare(keyHash, hash) == 0) {
        found = key;
      }
    });

    return difference == 0 ? found : null;
  }

  /// Compares two hashes without telling how much of them is equal.
  static int _compare(String left, String right) {
    if (left.length != right.length) {
      return 1;
    }

    var difference = 0;
    for (var index = 0; index < left.length; index++) {
      difference |= left.codeUnitAt(index) ^ right.codeUnitAt(index);
    }
    return difference;
  }
}

/// The hash of an API key.
///
/// The key is hashed with SHA-256, so the service only keeps the hash of the
/// key and a leak of the database does not leak the keys of the clients.
String hashApiKey(String key) => sha256.convert(utf8.encode(key)).toString();

/// Generates a new API key.
///
/// The key is long enough that it cannot be guessed, and it is drawn from a
/// cryptographic source.
String newApiKey() {
  final random = Random.secure();
  final bytes = List<int>.generate(32, (_) => random.nextInt(256));
  return base64Url.encode(bytes).replaceAll('=', '');
}
