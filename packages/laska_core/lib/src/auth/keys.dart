/// The generation of the keys of a service.
///
/// A service that signs its own tokens needs a key it keeps to itself, and a
/// service that verifies the tokens of another service needs the public part
/// of the key of that service. The functions here make both.
library;

import 'package:pointycastle/api.dart';
import 'package:pointycastle/ecc/api.dart';
import 'package:pointycastle/ecc/curves/secp256r1.dart';
import 'package:pointycastle/ecc/curves/secp384r1.dart';
import 'package:pointycastle/ecc/curves/secp521r1.dart';
import 'package:pointycastle/key_generators/api.dart';
import 'package:pointycastle/key_generators/ec_key_generator.dart';
import 'package:pointycastle/key_generators/rsa_key_generator.dart';
import 'package:pointycastle/random/fortuna_random.dart';

import 'bytes.dart';
import 'jwt.dart';

/// Generates a key of RSA for the tokens of a service.
///
/// The key holds its private part, so it may sign the tokens. The public part
/// is published in the key set of the service.
///
/// The generation of a key of 2048 bits takes a moment, because the primes of
/// the key are found by the operating system.
RsaJwtKey generateRsaKey({
  String? kid,
  int bits = 2048,
  JwtAlgorithm algorithm = JwtAlgorithm.rs256,
}) {
  final generator = RSAKeyGenerator()
    ..init(
      ParametersWithRandom(
        RSAKeyGeneratorParameters(BigInt.parse('65537'), bits, 64),
        _random,
      ),
    );
  final pair = generator.generateKeyPair();

  return RsaJwtKey.signing(
    pair.privateKey,
    kid: kid ?? newKeyId(),
    algorithm: algorithm,
  );
}

/// Generates a key of an elliptic curve for the tokens of a service.
///
/// The key holds its private part, so it may sign the tokens. The public part
/// is published in the key set of the service.
EcJwtKey generateEcKey({
  String? kid,
  JwtAlgorithm algorithm = JwtAlgorithm.es256,
}) {
  final domain = _domainOf(algorithm);
  final generator = ECKeyGenerator()
    ..init(
      ParametersWithRandom(
        ECKeyGeneratorParameters(domain),
        _random,
      ),
    );
  final pair = generator.generateKeyPair();

  return EcJwtKey.signing(
    pair.privateKey,
    kid: kid ?? newKeyId(),
    algorithm: algorithm,
  );
}

/// Generates a secret for the tokens of a service.
///
/// The secret is shared by the service and the callers, so it is never
/// published in a key set.
HmacJwtKey generateHmacKey({
  String? kid,
  JwtAlgorithm algorithm = JwtAlgorithm.hs256,
  int bytes = 32,
}) {
  return HmacJwtKey(
    randomBytes(bytes),
    kid: kid ?? newKeyId(),
    algorithm: algorithm,
  );
}

/// A new id of a key.
///
/// The id tells the receiver which key signed a token, so it must not repeat
/// itself over the life of the service.
String newKeyId() => 'k_${base64UrlEncode(randomBytes(9))}';

/// The parameters of the curve of the algorithm.
ECDomainParameters _domainOf(JwtAlgorithm algorithm) {
  switch (algorithm) {
    case JwtAlgorithm.es384:
      return ECCurve_secp384r1();
    case JwtAlgorithm.es512:
      return ECCurve_secp521r1();
    default:
      return ECCurve_secp256r1();
  }
}

/// The source of the random bytes of the generators of the keys.
///
/// The source is kept for the life of the process, so the keys of the service
/// do not all come from the same seed.
final SecureRandom _random = FortunaRandom()
  ..seed(KeyParameter(randomBytes(32)));
