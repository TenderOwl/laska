import 'dart:convert';
import 'dart:io';

import 'package:laska_core/laska_core.dart';

/// The result of the generation of a key.
class KeyGeneration {
  /// Creates a result.
  const KeyGeneration({
    required this.kid,
    required this.algorithm,
    required this.privateKeyFile,
    required this.jwksFile,
  });

  /// The id of the key.
  final String kid;

  /// The algorithm of the key.
  final JwtAlgorithm algorithm;

  /// The file the private key was written to.
  final String privateKeyFile;

  /// The file the key set was written to.
  final String jwksFile;
}

/// The error of a key that cannot be generated.
class KeyGenerationException implements Exception {
  /// Creates an error with the [message].
  KeyGenerationException(this.message);

  /// The description of the problem.
  final String message;

  @override
  String toString() => message;
}

/// Generates a key of the [algorithm] and writes it to the [directory].
///
/// The private key goes to `<directory>/<kid>.private.json`, and the key set
/// of the service goes to `<directory>/jwks.json`. The private file holds a
/// secret, so it must not be published.
KeyGeneration generateKey({
  required String directory,
  required JwtAlgorithm algorithm,
  String? kid,
  int bits = 2048,
}) {
  final JwtKey key;
  switch (algorithm.family) {
    case JwtKeyFamily.rsa:
      key = generateRsaKey(kid: kid, bits: bits, algorithm: algorithm);
    case JwtKeyFamily.ec:
      key = generateEcKey(kid: kid, algorithm: algorithm);
    case JwtKeyFamily.hmac:
      key = generateHmacKey(kid: kid, algorithm: algorithm);
  }

  final target = Directory(directory);
  target.createSync(recursive: true);

  final privateFile = File('${target.path}/${key.kid}.private.json');
  privateFile.writeAsStringSync(
    const JsonEncoder.withIndent('  ').convert(key.toJwk(includeSecret: true)),
  );

  final jwksFile = File('${target.path}/jwks.json');
  final existing = _readKeys(jwksFile);
  final keys = <JwtKey>[
    ...existing.where((old) => old.kid != key.kid),
    key,
  ];
  jwksFile.writeAsStringSync(
    const JsonEncoder.withIndent('  ').convert(jwksDocument(keys)),
  );

  return KeyGeneration(
    kid: key.kid!,
    algorithm: algorithm,
    privateKeyFile: privateFile.path,
    jwksFile: jwksFile.path,
  );
}

/// The keys of the key set in the [file], or an empty list when the file does
/// not hold a key set yet.
List<JwtKey> _readKeys(File file) {
  if (!file.existsSync()) {
    return const <JwtKey>[];
  }

  try {
    return parseJwks(file.readAsStringSync());
  } on JwksException {
    return const <JwtKey>[];
  }
}

/// The algorithm of the name [name].
JwtAlgorithm? keyAlgorithmOf(String name) {
  for (final algorithm in JwtAlgorithm.values) {
    if (algorithm.alg.toLowerCase() == name.toLowerCase()) {
      return algorithm;
    }
  }
  return null;
}
