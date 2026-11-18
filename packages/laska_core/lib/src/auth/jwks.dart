/// The key set of a service: the keys the callers may sign their tokens with.
///
/// The set is the JWKS of RFC 7517: a JSON document with the public keys of
/// the service. The service publishes the set, the callers fetch it and keep
/// it for a while, so a service may rotate its keys without a restart and
/// without the tokens of the callers breaking.
library;

import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:pointycastle/asymmetric/api.dart';
import 'package:pointycastle/ecc/api.dart';
import 'package:pointycastle/ecc/curves/secp256r1.dart';
import 'package:pointycastle/ecc/curves/secp384r1.dart';
import 'package:pointycastle/ecc/curves/secp521r1.dart';

import 'bytes.dart';
import 'jwt.dart';

/// The error of a key set that cannot be read.
class JwksException implements Exception {
  /// Creates an error with the [code] and the [message].
  JwksException(this.code, this.message);

  /// What is wrong with the key set, e.g. `jwks_malformed`.
  final String code;

  /// The description of the problem.
  final String message;

  @override
  String toString() => 'JwksException($code): $message';
}

/// The keys of the document of a key set.
///
/// The document holds the public keys of the service. Throws a [JwksException]
/// when the document is not a key set this framework understands.
List<JwtKey> parseJwks(String body) {
  Object? decoded;
  try {
    decoded = jsonDecode(body);
  } on FormatException {
    throw JwksException(
      'jwks_malformed',
      'The key set is not valid JSON',
    );
  }

  if (decoded is! Map<String, dynamic>) {
    throw JwksException(
      'jwks_malformed',
      'The key set is not a JSON object',
    );
  }

  final keys = decoded['keys'];
  if (keys is! List) {
    throw JwksException(
      'jwks_malformed',
      'The key set holds no list of keys',
    );
  }

  return keys.map((key) {
    if (key is! Map<String, dynamic>) {
      throw JwksException(
        'jwks_malformed',
        'A key of the set is not a JSON object',
      );
    }
    return keyFromJwk(key);
  }).toList(growable: false);
}

/// The key of the document of a key set.
///
/// Throws a [JwksException] when the document is not a key this framework
/// understands.
JwtKey keyFromJwk(Map<String, Object?> jwk) {
  final kty = jwk['kty'];
  final kid = jwk['kid'] as String?;
  final algorithm = _algorithmOf(jwk['alg']);

  switch (kty) {
    case 'oct':
      return HmacJwtKey(
        _bytesOf(jwk, 'k'),
        kid: kid,
        algorithm: algorithm ?? JwtAlgorithm.hs256,
      );

    case 'RSA':
      final modulus = bigIntFromBytes(_bytesOf(jwk, 'n'));
      final exponent = bigIntFromBytes(_bytesOf(jwk, 'e'));
      final secret = jwk['d'];
      if (secret is String) {
        // The document holds the private part of the key, so the key may sign
        // the tokens and not only verify them.
        return RsaJwtKey.signing(
          RSAPrivateKey(
            modulus,
            bigIntFromBytes(base64UrlDecode(secret)),
            bigIntFromBytes(_bytesOf(jwk, 'p')),
            bigIntFromBytes(_bytesOf(jwk, 'q')),
          ),
          kid: kid,
          algorithm: algorithm ?? JwtAlgorithm.rs256,
        );
      }
      return RsaJwtKey(
        publicKey: RSAPublicKey(modulus, exponent),
        kid: kid,
        algorithm: algorithm ?? JwtAlgorithm.rs256,
      );

    case 'EC':
      final curve = jwk['crv'];
      if (curve is! String) {
        throw JwksException(
          'jwk_malformed',
          'The key of the curve holds no curve',
        );
      }
      final domain = _curveOf(curve);
      if (domain == null) {
        throw JwksException(
          'jwk_unsupported',
          'The curve "$curve" is not supported',
        );
      }
      final x = bigIntFromBytes(_bytesOf(jwk, 'x'));
      final y = bigIntFromBytes(_bytesOf(jwk, 'y'));
      final secret = jwk['d'];
      if (secret is String) {
        return EcJwtKey.signing(
          ECPrivateKey(bigIntFromBytes(base64UrlDecode(secret)), domain),
          kid: kid,
          algorithm: algorithm ?? _algorithmOfCurve(curve),
        );
      }
      return EcJwtKey(
        publicKey: ECPublicKey(domain.curve.createPoint(x, y), domain),
        kid: kid,
        algorithm: algorithm ?? _algorithmOfCurve(curve),
      );

    default:
      throw JwksException(
        'jwk_unsupported',
        'The key of the type "$kty" is not supported',
      );
  }
}

/// The document of the key set of the [keys].
///
/// The document holds the public parts of the keys, so it may be published.
Map<String, Object?> jwksDocument(List<JwtKey> keys) => <String, Object?>{
      'keys': <Map<String, Object?>>[
        for (final key in keys) key.toJwk(),
      ],
    };

/// The cache of the key set of a service.
///
/// The cache holds the keys of the set and fetches the set again when it is
/// old. When a token names a key the cache does not know, the cache fetches
/// the set once more and looks again: this is how a service that rotates its
/// keys stays reachable for the callers that already got a fresh token.
///
/// The cache never fetches the set more than once per [minRefreshInterval],
/// so a flood of tokens with made up ids cannot turn the service into a
/// client of its own key set.
class JwksCache implements JwtKeySource {
  /// Creates a cache of the key set at the [uri].
  ///
  /// The [fetcher] reads the document of the set. It defaults to a plain
  /// HTTP GET, and a test may pass its own.
  JwksCache({
    required this.uri,
    this.ttl = const Duration(minutes: 15),
    this.minRefreshInterval = const Duration(seconds: 10),
    Future<String> Function(Uri uri)? fetcher,
    DateTime Function()? clock,
  })  : _fetcher = fetcher ?? _fetchOverHttp,
        _clock = clock ?? DateTime.now;

  /// Where the key set lives.
  final Uri uri;

  /// How long the keys of the set are used before the set is fetched again.
  final Duration ttl;

  /// The shortest time between two fetches of the set.
  final Duration minRefreshInterval;

  final Future<String> Function(Uri uri) _fetcher;
  final DateTime Function() _clock;

  List<JwtKey> _keys = const <JwtKey>[];
  DateTime? _fetchedAt;
  DateTime? _lastFetch;

  @override
  List<JwtKey> get keys => _keys;

  /// Fetches the key set again, whatever the age of the keys.
  ///
  /// The method does nothing when the set was fetched a moment ago, so a
  /// caller cannot use it to flood the service that publishes the set.
  Future<void> refresh() => _fetch();

  @override
  Future<List<JwtKey>> resolve(String? kid) async {
    await _fetchIfOld();

    var found = _select(kid);
    if (found.isEmpty && kid != null) {
      // The token names a key the set does not hold. The service may have
      // rotated its keys since the set was fetched, so the set is fetched
      // once more before the token is refused.
      await _fetch();
      found = _select(kid);
    }

    return found;
  }

  /// The keys of the set with the id [kid].
  List<JwtKey> _select(String? kid) {
    if (kid == null) {
      return _keys;
    }
    return _keys.where((key) => key.kid == kid).toList(growable: false);
  }

  Future<void> _fetchIfOld() async {
    final fetchedAt = _fetchedAt;
    if (fetchedAt == null || _clock().difference(fetchedAt) >= ttl) {
      await _fetch();
    }
  }

  Future<void> _fetch() async {
    final now = _clock();
    final lastFetch = _lastFetch;
    if (lastFetch != null && now.difference(lastFetch) < minRefreshInterval) {
      return;
    }
    _lastFetch = now;

    final body = await _fetcher(uri);
    _keys = parseJwks(body);
    _fetchedAt = now;
  }

  static Future<String> _fetchOverHttp(Uri uri) async {
    final response = await http.get(uri);
    if (response.statusCode != 200) {
      throw JwksException(
        'jwks_unavailable',
        'The key set answered with the status ${response.statusCode}',
      );
    }
    return response.body;
  }
}

/// The algorithm of the name [alg].
JwtAlgorithm? _algorithmOf(Object? alg) {
  if (alg == null) {
    return null;
  }
  if (alg is! String) {
    throw JwksException(
      'jwk_malformed',
      'The algorithm of the key is not a name',
    );
  }

  final algorithm = JwtAlgorithm.parse(alg);
  if (algorithm == null) {
    throw JwksException(
      'jwk_unsupported',
      'The algorithm "$alg" is not supported',
    );
  }
  return algorithm;
}

/// The bytes of the part [name] of the key.
List<int> _bytesOf(Map<String, Object?> jwk, String name) {
  final value = jwk[name];
  if (value is! String) {
    throw JwksException(
      'jwk_malformed',
      'The key holds no "$name"',
    );
  }
  try {
    return base64UrlDecode(value);
  } on FormatException {
    throw JwksException(
      'jwk_malformed',
      'The "$name" of the key is not base64url',
    );
  }
}

/// The parameters of the curve [name].
ECDomainParameters? _curveOf(String name) {
  switch (name) {
    case 'P-256':
      return ECCurve_secp256r1();
    case 'P-384':
      return ECCurve_secp384r1();
    case 'P-521':
      return ECCurve_secp521r1();
    default:
      return null;
  }
}

/// The algorithm of the curve [name].
JwtAlgorithm _algorithmOfCurve(String name) {
  switch (name) {
    case 'P-384':
      return JwtAlgorithm.es384;
    case 'P-521':
      return JwtAlgorithm.es512;
    default:
      return JwtAlgorithm.es256;
  }
}
