/// JSON Web Tokens — the tokens a service hands to its callers.
///
/// A token is a header, a set of claims and a signature. The service signs the
/// tokens it issues and verifies the tokens of its callers. The verification
/// never trusts the header: the algorithm of the token must be the algorithm
/// of the key that verifies it, so a caller cannot talk the service into a
/// weaker algorithm than the service expects.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' hide Digest;
import 'package:pointycastle/api.dart';
import 'package:pointycastle/asymmetric/api.dart';
import 'package:pointycastle/ecc/api.dart';
import 'package:pointycastle/signers/ecdsa_signer.dart';
import 'package:pointycastle/signers/rsa_signer.dart';
import 'package:pointycastle/random/fortuna_random.dart';

import 'bytes.dart';
import 'digest.dart';

/// The family of the key an algorithm needs.
enum JwtKeyFamily {
  /// The key is a secret shared by the sender and the receiver.
  hmac,

  /// The key is a pair of RSA keys.
  rsa,

  /// The key is a pair of elliptic curve keys.
  ec,
}

/// The algorithm of the signature of a token.
enum JwtAlgorithm {
  /// HMAC with SHA-256.
  hs256('HS256', JwtKeyFamily.hmac, 256),

  /// HMAC with SHA-384.
  hs384('HS384', JwtKeyFamily.hmac, 384),

  /// HMAC with SHA-512.
  hs512('HS512', JwtKeyFamily.hmac, 512),

  /// RSASSA-PKCS1-v1_5 with SHA-256.
  rs256('RS256', JwtKeyFamily.rsa, 256),

  /// RSASSA-PKCS1-v1_5 with SHA-384.
  rs384('RS384', JwtKeyFamily.rsa, 384),

  /// RSASSA-PKCS1-v1_5 with SHA-512.
  rs512('RS512', JwtKeyFamily.rsa, 512),

  /// ECDSA with P-256 and SHA-256.
  es256('ES256', JwtKeyFamily.ec, 256),

  /// ECDSA with P-384 and SHA-384.
  es384('ES384', JwtKeyFamily.ec, 384),

  /// ECDSA with P-521 and SHA-512.
  es512('ES512', JwtKeyFamily.ec, 521);

  const JwtAlgorithm(this.alg, this.family, this.hashBits);

  /// The name of the algorithm in the header of a token, e.g. `RS256`.
  final String alg;

  /// The family of the key the algorithm needs.
  final JwtKeyFamily family;

  /// The size of the hash of the algorithm, in bits.
  final int hashBits;

  /// Whether the algorithm signs with a secret shared by the sender and the
  /// receiver.
  bool get isHmac => family == JwtKeyFamily.hmac;

  /// Parses the algorithm of a header, e.g. `RS256`.
  ///
  /// Returns `null` when the name is not an algorithm this framework knows.
  /// The token with an unknown algorithm is never verified, because a token
  /// that asks for something else must not fall back to a weaker algorithm.
  static JwtAlgorithm? parse(String alg) {
    for (final algorithm in JwtAlgorithm.values) {
      if (algorithm.alg == alg) {
        return algorithm;
      }
    }
    return null;
  }
}

/// A key that signs or verifies the tokens of a service.
///
/// The keys of a service are listed in the verifier, so the service may
/// rotate its keys: the old key stays in the list until the tokens it signed
/// expire.
sealed class JwtKey {
  /// Creates a key.
  const JwtKey({required this.algorithm, this.kid});

  /// The algorithm the key works with.
  final JwtAlgorithm algorithm;

  /// The id of the key, written in the header of the token.
  ///
  /// The id tells the receiver which key signed the token, so the tokens of
  /// the old key stay valid while the new key is already in use.
  final String? kid;

  /// Whether the key can sign tokens.
  bool get canSign => false;

  /// Signs the [message].
  List<int> sign(List<int> message) =>
      throw UnsupportedError('The key cannot sign tokens');

  /// Whether the [signature] is the signature of the [message].
  bool verify(List<int> message, List<int> signature) =>
      throw UnsupportedError('The key cannot verify tokens');

  /// The key in the JWK format.
  ///
  /// The secret of an HMAC key is only in the document when [includeSecret]
  /// is set, because a document the world may read must not hold a secret.
  Map<String, Object?> toJwk({bool includeSecret = false}) =>
      throw UnsupportedError('The key has no JWK form');
}

/// A key that signs a token with a secret shared with the receiver.
final class HmacJwtKey extends JwtKey {
  /// Creates a key for the [secret].
  ///
  /// The secret must not be empty: a key without a secret would sign every
  /// token with the same, known, value.
  HmacJwtKey(
    List<int> secret, {
    super.kid,
    JwtAlgorithm algorithm = JwtAlgorithm.hs256,
  })  : secret = Uint8List.fromList(secret),
        super(algorithm: algorithm) {
    if (!algorithm.isHmac) {
      throw ArgumentError.value(
        algorithm,
        'algorithm',
        'An HMAC key needs an HS* algorithm',
      );
    }
    if (secret.isEmpty) {
      throw ArgumentError.value(
        secret.length,
        'secret',
        'The secret of an HMAC key must not be empty',
      );
    }
  }

  /// The secret of the key.
  final Uint8List secret;

  @override
  bool get canSign => true;

  @override
  List<int> sign(List<int> message) => _hmac(algorithm, secret, message);

  @override
  bool verify(List<int> message, List<int> signature) =>
      constantTimeEquals(sign(message), signature);

  @override
  Map<String, Object?> toJwk({bool includeSecret = false}) => <String, Object?>{
        'kty': 'oct',
        if (kid != null) 'kid': kid,
        'alg': algorithm.alg,
        if (includeSecret) 'k': base64UrlEncode(secret),
      };
}

/// A key of RSA that signs or verifies the tokens of a service.
final class RsaJwtKey extends JwtKey {
  /// Creates a key that verifies the tokens signed with [publicKey].
  RsaJwtKey({
    required this.publicKey,
    RSAPrivateKey? privateKey,
    super.kid,
    JwtAlgorithm algorithm = JwtAlgorithm.rs256,
  })  : _privateKey = privateKey,
        super(algorithm: algorithm) {
    if (algorithm.family != JwtKeyFamily.rsa) {
      throw ArgumentError.value(
        algorithm,
        'algorithm',
        'An RSA key needs an RS* algorithm',
      );
    }
  }

  /// Creates a key that signs the tokens with [privateKey].
  ///
  /// The public part of the key is taken from the private one, so the service
  /// may publish it in the key set of the service.
  factory RsaJwtKey.signing(
    RSAPrivateKey privateKey, {
    String? kid,
    JwtAlgorithm algorithm = JwtAlgorithm.rs256,
  }) {
    final publicKey = RSAPublicKey(
      privateKey.modulus!,
      privateKey.publicExponent!,
    );
    return RsaJwtKey(
      publicKey: publicKey,
      privateKey: privateKey,
      kid: kid,
      algorithm: algorithm,
    );
  }

  /// The public part of the key.
  final RSAPublicKey publicKey;

  final RSAPrivateKey? _privateKey;

  @override
  bool get canSign => _privateKey != null;

  @override
  List<int> sign(List<int> message) {
    final privateKey = _privateKey;
    if (privateKey == null) {
      throw StateError('The key has no private part and cannot sign tokens');
    }

    final signer =
        RSASigner(_digestOf(algorithm), _digestIdentifierOf(algorithm))
          ..init(true, PrivateKeyParameter<RSAPrivateKey>(privateKey));
    return signer.generateSignature(Uint8List.fromList(message)).bytes;
  }

  @override
  bool verify(List<int> message, List<int> signature) {
    final signer =
        RSASigner(_digestOf(algorithm), _digestIdentifierOf(algorithm))
          ..init(false, PublicKeyParameter<RSAPublicKey>(publicKey));
    try {
      return signer.verifySignature(
        Uint8List.fromList(message),
        RSASignature(Uint8List.fromList(signature)),
      );
    } catch (_) {
      // A signature of the wrong length is not a signature of this message.
      return false;
    }
  }

  @override
  Map<String, Object?> toJwk({bool includeSecret = false}) {
    final document = <String, Object?>{
      'kty': 'RSA',
      if (kid != null) 'kid': kid,
      'alg': algorithm.alg,
      'n': base64UrlEncode(bigIntToBytes(publicKey.modulus!)),
      'e': base64UrlEncode(bigIntToBytes(publicKey.publicExponent!)),
    };

    final privateKey = _privateKey;
    if (includeSecret && privateKey != null) {
      document['d'] =
          base64UrlEncode(bigIntToBytes(privateKey.privateExponent!));
      document['p'] = base64UrlEncode(bigIntToBytes(privateKey.p!));
      document['q'] = base64UrlEncode(bigIntToBytes(privateKey.q!));
    }

    return document;
  }
}

/// A key of an elliptic curve that signs or verifies the tokens of a service.
final class EcJwtKey extends JwtKey {
  /// Creates a key that verifies the tokens signed with [publicKey].
  EcJwtKey({
    required this.publicKey,
    ECPrivateKey? privateKey,
    super.kid,
    JwtAlgorithm algorithm = JwtAlgorithm.es256,
  })  : _privateKey = privateKey,
        super(algorithm: algorithm) {
    if (algorithm.family != JwtKeyFamily.ec) {
      throw ArgumentError.value(
        algorithm,
        'algorithm',
        'An elliptic curve key needs an ES* algorithm',
      );
    }
  }

  /// Creates a key that signs the tokens with [privateKey].
  factory EcJwtKey.signing(
    ECPrivateKey privateKey, {
    String? kid,
    JwtAlgorithm algorithm = JwtAlgorithm.es256,
  }) {
    final publicKey = ECPublicKey(
      privateKey.parameters!.G * privateKey.d!,
      privateKey.parameters,
    );
    return EcJwtKey(
      publicKey: publicKey,
      privateKey: privateKey,
      kid: kid,
      algorithm: algorithm,
    );
  }

  /// The public part of the key.
  final ECPublicKey publicKey;

  final ECPrivateKey? _privateKey;

  /// The size of one half of the signature, in bytes.
  int get _coordinateSize {
    final parameters = publicKey.parameters;
    if (parameters == null) {
      throw StateError('The key has no domain parameters');
    }
    return (parameters.n.bitLength + 7) ~/ 8;
  }

  @override
  bool get canSign => _privateKey != null;

  @override
  List<int> sign(List<int> message) {
    final privateKey = _privateKey;
    if (privateKey == null) {
      throw StateError('The key has no private part and cannot sign tokens');
    }

    final signer = ECDSASigner(_digestOf(algorithm))
      ..init(
        true,
        ParametersWithRandom(
          PrivateKeyParameter<ECPrivateKey>(privateKey),
          _random,
        ),
      );
    final signature =
        signer.generateSignature(Uint8List.fromList(message)) as ECSignature;
    return <int>[
      ..._toFixedBytes(signature.r, _coordinateSize),
      ..._toFixedBytes(signature.s, _coordinateSize),
    ];
  }

  @override
  bool verify(List<int> message, List<int> signature) {
    final size = _coordinateSize;
    if (signature.length != size * 2) {
      return false;
    }

    final signer = ECDSASigner(_digestOf(algorithm))
      ..init(false, PublicKeyParameter<ECPublicKey>(publicKey));
    try {
      return signer.verifySignature(
        Uint8List.fromList(message),
        ECSignature(
          _fromFixedBytes(signature.sublist(0, size)),
          _fromFixedBytes(signature.sublist(size)),
        ),
      );
    } catch (_) {
      return false;
    }
  }

  /// The name of the curve of the key, e.g. `P-256`.
  String get curveName {
    final parameters = publicKey.parameters;
    if (parameters == null) {
      throw StateError('The key has no domain parameters');
    }
    switch (parameters.n.bitLength) {
      case 256:
        return 'P-256';
      case 384:
        return 'P-384';
      case 521:
        return 'P-521';
      default:
        return 'P-${parameters.n.bitLength}';
    }
  }

  @override
  Map<String, Object?> toJwk({bool includeSecret = false}) {
    final point = publicKey.Q;
    if (point == null) {
      throw StateError('The key has no public point');
    }
    final size = _coordinateSize;

    final document = <String, Object?>{
      'kty': 'EC',
      if (kid != null) 'kid': kid,
      'alg': algorithm.alg,
      'crv': curveName,
      'x': base64UrlEncode(_toFixedBytes(point.x!.toBigInteger()!, size)),
      'y': base64UrlEncode(_toFixedBytes(point.y!.toBigInteger()!, size)),
    };

    final privateKey = _privateKey;
    if (includeSecret && privateKey != null) {
      document['d'] = base64UrlEncode(bigIntToBytes(privateKey.d!));
    }

    return document;
  }
}

/// The claims of a token.
///
/// The claims are the facts the token carries: who the caller is, what the
/// caller may do and until when the token is good.
class JwtClaims {
  /// Creates a set of claims.
  JwtClaims({
    this.issuer,
    this.subject,
    List<String>? audience,
    this.expiresAt,
    this.notBefore,
    this.issuedAt,
    this.jwtId,
    Map<String, Object?>? claims,
  })  : audience = audience ?? const <String>[],
        claims = claims ?? <String, Object?>{};

  /// The issuer of the token, e.g. `https://auth.example.com`.
  final String? issuer;

  /// The subject of the token, the id of the caller.
  final String? subject;

  /// The services the token is meant for.
  final List<String> audience;

  /// When the token stops being valid.
  final DateTime? expiresAt;

  /// When the token starts being valid.
  final DateTime? notBefore;

  /// When the token was issued.
  final DateTime? issuedAt;

  /// The unique id of the token.
  final String? jwtId;

  /// The claims of the service, e.g. the scopes of the caller.
  final Map<String, Object?> claims;

  /// The scopes of the caller.
  ///
  /// The scopes are read from the `scope` claim, which holds them separated by
  /// spaces, or from the `scp` claim, which holds them as a list.
  List<String> get scopes {
    final scope = claims['scope'];
    if (scope is String) {
      return scope
          .split(' ')
          .where((value) => value.isNotEmpty)
          .toList(growable: false);
    }

    final scp = claims['scp'];
    if (scp is List) {
      return scp.map((value) => value.toString()).toList(growable: false);
    }

    return const <String>[];
  }

  /// The claims in the JSON form of the payload of a token.
  Map<String, Object?> toJson() => <String, Object?>{
        if (issuer != null) 'iss': issuer,
        if (subject != null) 'sub': subject,
        if (audience.isNotEmpty) 'aud': audience,
        if (expiresAt != null) 'exp': _seconds(expiresAt!),
        if (notBefore != null) 'nbf': _seconds(notBefore!),
        if (issuedAt != null) 'iat': _seconds(issuedAt!),
        if (jwtId != null) 'jti': jwtId,
        ...claims,
      };

  /// Reads the claims out of the payload of a token.
  static JwtClaims fromJson(Map<String, Object?> json) {
    final audience = <String>[];
    final rawAudience = json['aud'];
    if (rawAudience is String) {
      audience.add(rawAudience);
    } else if (rawAudience is List) {
      for (final value in rawAudience) {
        audience.add(value.toString());
      }
    }

    final known = <String>{
      'iss',
      'sub',
      'aud',
      'exp',
      'nbf',
      'iat',
      'jti',
    };
    final custom = <String, Object?>{
      for (final entry in json.entries)
        if (!known.contains(entry.key)) entry.key: entry.value,
    };

    return JwtClaims(
      issuer: json['iss'] as String?,
      subject: json['sub'] as String?,
      audience: audience,
      expiresAt: _date(json['exp']),
      notBefore: _date(json['nbf']),
      issuedAt: _date(json['iat']),
      jwtId: json['jti'] as String?,
      claims: custom,
    );
  }
}

/// A token: its header, its claims and its signature.
class Jwt {
  /// Creates a token.
  const Jwt({
    required this.header,
    required this.claims,
    required this.signature,
  });

  /// The header of the token.
  final Map<String, Object?> header;

  /// The claims of the token.
  final JwtClaims claims;

  /// The signature of the token.
  final List<int> signature;

  /// The subject of the token, the id of the caller.
  String? get subject => claims.subject;

  /// The scopes of the caller.
  List<String> get scopes => claims.scopes;
}

/// The error of a token that cannot be used.
///
/// The [code] tells what is wrong, so the service may answer with a code of
/// its own without leaking the details of the token.
class JwtException implements Exception {
  /// Creates an error with the [code] and the [message].
  JwtException(this.code, this.message);

  /// What is wrong with the token, e.g. `token_expired`.
  final String code;

  /// The description of the problem.
  final String message;

  @override
  String toString() => 'JwtException($code): $message';
}

/// The signer of the tokens of a service.
class JwtSigner {
  /// Creates a signer that signs with the [key].
  JwtSigner(this.key) {
    if (!key.canSign) {
      throw ArgumentError.value(
        key,
        'key',
        'The key has no private part and cannot sign tokens',
      );
    }
  }

  /// The key the tokens are signed with.
  final JwtKey key;

  /// Signs the [claims] into a token.
  ///
  /// The header of the token holds the algorithm of the key and the id of the
  /// key, so the receiver knows which key to verify the token with.
  String sign(JwtClaims claims, {Map<String, Object?>? header}) {
    final headerJson = <String, Object?>{
      'alg': key.algorithm.alg,
      'typ': 'JWT',
      if (key.kid != null) 'kid': key.kid,
      ...?header,
    };

    final encodedHeader = base64UrlEncode(utf8.encode(jsonEncode(headerJson)));
    final encodedPayload =
        base64UrlEncode(utf8.encode(jsonEncode(claims.toJson())));
    final signingInput = utf8.encode('$encodedHeader.$encodedPayload');
    final signature = key.sign(signingInput);

    return '$encodedHeader.$encodedPayload.${base64UrlEncode(signature)}';
  }
}

/// The source of the keys a verifier trusts.
///
/// The source may fetch the keys again, so a service that rotates its keys
/// finds the new key without a restart. A service may write its own source,
/// e.g. one that reads the keys from a database.
abstract class JwtKeySource {
  const JwtKeySource();

  /// The keys the source knows right now.
  List<JwtKey> get keys;

  /// The keys the source offers for the token of the id [kid].
  ///
  /// The method may fetch the keys again. When the token names a key the
  /// source does not know, the source looks for it once more, so a token
  /// signed with a fresh key is accepted while the old key is still in use.
  Future<List<JwtKey>> resolve(String? kid);
}

/// The keys of a service that are known upfront.
final class StaticJwtKeySource extends JwtKeySource {
  /// Creates a source for the [keys].
  const StaticJwtKeySource(this._keys);

  final List<JwtKey> _keys;

  @override
  List<JwtKey> get keys => _keys;

  @override
  Future<List<JwtKey>> resolve(String? kid) async =>
      kid == null ? _keys : _keys.where((key) => key.kid == kid).toList();
}

/// The parts of a token that the verifier reads.
class _ParsedToken {
  const _ParsedToken({
    required this.header,
    required this.algorithm,
    required this.kid,
    required this.claims,
    required this.signingInput,
    required this.signature,
  });

  final Map<String, Object?> header;
  final JwtAlgorithm algorithm;
  final String? kid;
  final JwtClaims claims;
  final List<int> signingInput;
  final List<int> signature;
}

/// The verifier of the tokens of the callers of a service.
///
/// The verifier holds every key the service accepts, so the service may
/// rotate its keys without invalidating the tokens that are still alive.
class JwtVerifier {
  /// Creates a verifier for the [keys].
  ///
  /// When the [issuer] is set, a token of another issuer is refused. When the
  /// [audience] is not empty, a token meant for another service is refused.
  /// The [leeway] is the time the clocks of the services may differ by.
  JwtVerifier({
    required List<JwtKey> keys,
    String? issuer,
    List<String>? audience,
    Duration leeway = const Duration(seconds: 30),
    DateTime Function()? clock,
  }) : this.withSource(
          StaticJwtKeySource(List<JwtKey>.unmodifiable(keys)),
          issuer: issuer,
          audience: audience,
          leeway: leeway,
          clock: clock,
        );

  /// Creates a verifier for the keys of the [source].
  JwtVerifier.withSource(
    JwtKeySource source, {
    this.issuer,
    List<String>? audience,
    this.leeway = const Duration(seconds: 30),
    DateTime Function()? clock,
  })  : _source = source,
        audience = List<String>.unmodifiable(audience ?? const <String>[]),
        _clock = clock ?? DateTime.now;

  final JwtKeySource _source;

  /// The keys the tokens are verified with.
  List<JwtKey> get keys => _source.keys;

  /// The issuer the tokens must have, when it is set.
  final String? issuer;

  /// The services the tokens must be meant for, when it is not empty.
  final List<String> audience;

  /// How much the clocks of the services may differ by.
  final Duration leeway;

  final DateTime Function() _clock;

  /// Verifies the [token] and returns it.
  ///
  /// Throws a [JwtException] when the token cannot be used. The method only
  /// looks at the keys the verifier knows, so it never waits for the network.
  Jwt verify(String token) {
    final parsed = _parse(token);
    final candidates = parsed.kid == null
        ? keys
        : keys.where((key) => key.kid == parsed.kid).toList();
    return _check(parsed, _select(candidates, parsed));
  }

  /// Verifies the [token] and returns it.
  ///
  /// The method asks the source of the keys for the key of the token, so a
  /// token signed with a fresh key is accepted even when the set of the keys
  /// was fetched before the rotation.
  ///
  /// Throws a [JwtException] when the token cannot be used.
  Future<Jwt> verifyAsync(String token) async {
    final parsed = _parse(token);
    final candidates = await _source.resolve(parsed.kid);
    return _check(parsed, _select(candidates, parsed));
  }

  /// The parts of a token that the verifier reads.
  _ParsedToken _parse(String token) {
    final parts = token.split('.');
    if (parts.length != 3) {
      throw JwtException(
        'token_malformed',
        'The token is not a JWT: it does not have three parts',
      );
    }

    final header = _decodeJson(parts[0], 'header');
    final algorithm = _algorithmOf(header);
    final kid = header['kid'];

    final payload = _decodeJson(parts[1], 'payload');
    final claims = JwtClaims.fromJson(payload);

    return _ParsedToken(
      header: header,
      algorithm: algorithm,
      kid: kid is String && kid.isNotEmpty ? kid : null,
      claims: claims,
      signingInput: utf8.encode('${parts[0]}.${parts[1]}'),
      signature: base64UrlDecode(parts[2]),
    );
  }

  /// The key of the candidates that verifies the token.
  JwtKey _select(List<JwtKey> candidates, _ParsedToken parsed) {
    if (candidates.isEmpty) {
      throw JwtException(
        'key_not_found',
        parsed.kid != null
            ? 'The service does not know the key "${parsed.kid}" of the token'
            : 'The service does not know the key of the token',
      );
    }

    // The algorithm of the token must be the algorithm of the key. A token
    // that asks for another algorithm is never verified with another key.
    final matching = candidates
        .where((key) => key.algorithm == parsed.algorithm)
        .toList(growable: false);

    if (matching.isEmpty) {
      throw JwtException(
        'algorithm_mismatch',
        'The token is signed with ${parsed.algorithm.alg}, '
            'but the service expects ${candidates.first.algorithm.alg}',
      );
    }

    if (matching.length > 1) {
      throw JwtException(
        'key_ambiguous',
        'The service knows more than one key for the token',
      );
    }

    return matching.first;
  }

  /// Checks the signature and the claims of the token.
  Jwt _check(_ParsedToken parsed, JwtKey key) {
    if (!key.verify(parsed.signingInput, parsed.signature)) {
      throw JwtException(
        'signature_invalid',
        'The signature of the token does not match its content',
      );
    }

    _checkTime(parsed.claims);
    _checkIssuer(parsed.claims);
    _checkAudience(parsed.claims);

    return Jwt(
      header: parsed.header,
      claims: parsed.claims,
      signature: parsed.signature,
    );
  }

  /// The algorithm of the header of the token.
  JwtAlgorithm _algorithmOf(Map<String, Object?> header) {
    final alg = header['alg'];
    if (alg is! String || alg.isEmpty) {
      throw JwtException(
        'token_malformed',
        'The header of the token holds no algorithm',
      );
    }

    final algorithm = JwtAlgorithm.parse(alg);
    if (algorithm == null) {
      throw JwtException(
        'algorithm_unsupported',
        'The token is signed with the unsupported algorithm "$alg"',
      );
    }
    return algorithm;
  }

  void _checkTime(JwtClaims claims) {
    final now = _clock();

    final expiresAt = claims.expiresAt;
    if (expiresAt != null && now.isAfter(expiresAt.add(leeway))) {
      throw JwtException('token_expired', 'The token has expired');
    }

    final notBefore = claims.notBefore;
    if (notBefore != null && now.add(leeway).isBefore(notBefore)) {
      throw JwtException(
        'token_not_yet_valid',
        'The token is not valid yet',
      );
    }
  }

  void _checkIssuer(JwtClaims claims) {
    final expected = issuer;
    if (expected == null) {
      return;
    }
    if (claims.issuer != expected) {
      throw JwtException(
        'issuer_mismatch',
        'The token is issued by another service',
      );
    }
  }

  void _checkAudience(JwtClaims claims) {
    if (audience.isEmpty) {
      return;
    }
    for (final expected in audience) {
      if (claims.audience.contains(expected)) {
        return;
      }
    }
    throw JwtException(
      'audience_mismatch',
      'The token is not meant for this service',
    );
  }
}

/// The source of the random bytes of the signatures of the elliptic curves.
///
/// The signer of the curve needs a source of random bytes for the nonce of
/// every signature, so the source is kept for the life of the process.
final SecureRandom _random = FortunaRandom()
  ..seed(KeyParameter(randomBytes(32)));

/// The digest of the algorithm.
Digest _digestOf(JwtAlgorithm algorithm) {
  switch (algorithm) {
    case JwtAlgorithm.hs256:
    case JwtAlgorithm.rs256:
    case JwtAlgorithm.es256:
      return Sha2Digest.sha256();
    case JwtAlgorithm.hs384:
    case JwtAlgorithm.rs384:
    case JwtAlgorithm.es384:
      return Sha2Digest.sha384();
    case JwtAlgorithm.hs512:
    case JwtAlgorithm.rs512:
    case JwtAlgorithm.es512:
      return Sha2Digest.sha512();
  }
}

/// The DER identifier of the digest, as the signer of RSA needs it.
String _digestIdentifierOf(JwtAlgorithm algorithm) {
  switch (algorithm) {
    case JwtAlgorithm.rs256:
    case JwtAlgorithm.es256:
      return '0609608648016503040201';
    case JwtAlgorithm.rs384:
    case JwtAlgorithm.es384:
      return '0609608648016503040202';
    case JwtAlgorithm.rs512:
    case JwtAlgorithm.es512:
      return '0609608648016503040203';
    default:
      throw ArgumentError.value(
        algorithm,
        'algorithm',
        'The algorithm does not sign with RSA',
      );
  }
}

/// The HMAC of the [message] with the [secret].
List<int> _hmac(JwtAlgorithm algorithm, List<int> secret, List<int> message) {
  final Hash hash;
  switch (algorithm) {
    case JwtAlgorithm.hs256:
      hash = sha256;
    case JwtAlgorithm.hs384:
      hash = sha384;
    case JwtAlgorithm.hs512:
      hash = sha512;
    default:
      throw ArgumentError.value(
        algorithm,
        'algorithm',
        'The algorithm does not sign with HMAC',
      );
  }
  return Hmac(hash, secret).convert(message).bytes;
}

/// The bytes of [value], padded to [size] bytes.
List<int> _toFixedBytes(BigInt value, int size) {
  final hex = value.toRadixString(16);
  final padded = hex.length.isOdd ? '0$hex' : hex;

  final bytes = <int>[];
  for (var index = 0; index < padded.length; index += 2) {
    bytes.add(int.parse(padded.substring(index, index + 2), radix: 16));
  }

  if (bytes.length > size) {
    throw ArgumentError.value(
      value,
      'value',
      'The value does not fit in $size bytes',
    );
  }

  return <int>[
    ...List<int>.filled(size - bytes.length, 0),
    ...bytes,
  ];
}

/// The number of the bytes.
BigInt _fromFixedBytes(List<int> bytes) {
  var result = BigInt.zero;
  for (final byte in bytes) {
    result = (result << 8) | BigInt.from(byte);
  }
  return result;
}

/// The date of the claim, e.g. `exp`.
DateTime? _date(Object? value) {
  if (value is num) {
    return DateTime.fromMillisecondsSinceEpoch(
      value.toInt() * 1000,
      isUtc: true,
    );
  }
  return null;
}

/// The seconds of the [date] since the epoch.
int _seconds(DateTime date) => date.toUtc().millisecondsSinceEpoch ~/ 1000;

/// The JSON object of the part of a token.
Map<String, Object?> _decodeJson(String part, String name) {
  Object? decoded;
  try {
    decoded = jsonDecode(utf8.decode(base64UrlDecode(part)));
  } on FormatException {
    throw JwtException(
      'token_malformed',
      'The $name of the token is not valid JSON',
    );
  }

  if (decoded is! Map<String, dynamic>) {
    throw JwtException(
      'token_malformed',
      'The $name of the token is not a JSON object',
    );
  }

  return decoded;
}
