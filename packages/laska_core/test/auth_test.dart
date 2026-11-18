import 'dart:convert';

import 'package:laska_core/laska_core.dart';
import 'package:pointycastle/api.dart';
import 'package:pointycastle/asymmetric/api.dart';
import 'package:pointycastle/ecc/api.dart';
import 'package:pointycastle/ecc/curves/secp256r1.dart';
import 'package:pointycastle/key_generators/api.dart';
import 'package:pointycastle/key_generators/ec_key_generator.dart';
import 'package:pointycastle/key_generators/rsa_key_generator.dart';
import 'package:pointycastle/random/fortuna_random.dart';
import 'package:test/test.dart';

Request _request(
  String method,
  String path, {
  Map<String, String>? headers,
}) =>
    Request(
      method: method,
      path: Uri.parse(path).path,
      uri: path,
      query: const <String, String>{},
      headers: headers ?? const <String, String>{},
    );

Response _ok() => Response.text('ok');

/// The token of [claims], signed with [key].
String _token(JwtKey key, JwtClaims claims) => JwtSigner(key).sign(claims);

/// The token with the header [header], the payload of [claims] and no valid
/// signature.
String _tokenWithHeader(
  JwtKey key,
  JwtClaims claims,
  Map<String, Object?> header,
) {
  final encodedHeader =
      base64Url.encode(utf8.encode(jsonEncode(header))).replaceAll('=', '');
  final encodedPayload = base64Url
      .encode(utf8.encode(jsonEncode(claims.toJson())))
      .replaceAll('=', '');
  return '$encodedHeader.$encodedPayload.c2lnbmF0dXJl';
}

/// The code of the error of [token] in the [verifier].
String _failureOf(JwtVerifier verifier, String token) {
  try {
    verifier.verify(token);
  } on JwtException catch (error) {
    return error.code;
  }
  return 'no error';
}

/// The source of the random bytes of the generators of the keys.
SecureRandom _random() => FortunaRandom()..seed(KeyParameter(randomBytes(32)));

/// The pair of the RSA keys of the test.
///
/// The strength is the smallest one the tests need: the point of the test is
/// that the token is signed and verified, not that the key is unbreakable.
({RSAPublicKey publicKey, RSAPrivateKey privateKey}) _rsaKeys() {
  final generator = RSAKeyGenerator()
    ..init(
      ParametersWithRandom(
        RSAKeyGeneratorParameters(BigInt.parse('65537'), 1024, 64),
        _random(),
      ),
    );
  final pair = generator.generateKeyPair();
  return (publicKey: pair.publicKey, privateKey: pair.privateKey);
}

/// The pair of the EC keys of the test on the curve P-256.
({ECPublicKey publicKey, ECPrivateKey privateKey}) _ecKeys() {
  final generator = ECKeyGenerator()
    ..init(
      ParametersWithRandom(
        ECKeyGeneratorParameters(ECCurve_secp256r1()),
        _random(),
      ),
    );
  final pair = generator.generateKeyPair();
  return (publicKey: pair.publicKey, privateKey: pair.privateKey);
}

void main() {
  group('JwtSigner and JwtVerifier', () {
    final key = HmacJwtKey(utf8.encode('a secret of the service'));

    test('signs a token and verifies it', () {
      final token = _token(
        key,
        JwtClaims(
          issuer: 'https://auth.example.com',
          subject: 'user-1',
          audience: const <String>['users'],
        ),
      );

      final jwt = JwtVerifier(keys: <JwtKey>[key]).verify(token);

      expect(jwt.subject, 'user-1');
      expect(jwt.claims.issuer, 'https://auth.example.com');
      expect(jwt.claims.audience, <String>['users']);
    });

    test('keeps the claims of the service', () {
      final token = _token(
        key,
        JwtClaims(
          subject: 'user-1',
          claims: <String, Object?>{'scope': 'users:read users:write'},
        ),
      );

      final jwt = JwtVerifier(keys: <JwtKey>[key]).verify(token);

      expect(jwt.scopes, <String>['users:read', 'users:write']);
    });

    test('refuses a token whose payload was changed', () {
      final token = _token(key, JwtClaims(subject: 'user-1'));
      final parts = token.split('.');
      final payload = jsonDecode(
        utf8.decode(base64Url.decode(base64Url.normalize(parts[1]))),
      ) as Map<String, dynamic>;
      payload['sub'] = 'admin';
      final forged =
          '${parts[0]}.${base64Url.encode(utf8.encode(jsonEncode(payload))).replaceAll('=', '')}.${parts[2]}';

      expect(
        _failureOf(JwtVerifier(keys: <JwtKey>[key]), forged),
        'signature_invalid',
      );
    });

    test('refuses an expired token', () {
      final now = DateTime.utc(2026, 1, 1, 12);
      final token = _token(
        key,
        JwtClaims(
          subject: 'user-1',
          issuedAt: now.subtract(const Duration(hours: 2)),
          expiresAt: now.subtract(const Duration(hours: 1)),
        ),
      );

      final verifier = JwtVerifier(
        keys: <JwtKey>[key],
        leeway: Duration.zero,
        clock: () => now,
      );

      expect(_failureOf(verifier, token), 'token_expired');
    });

    test('refuses a token that is not valid yet', () {
      final now = DateTime.utc(2026, 1, 1, 12);
      final token = _token(
        key,
        JwtClaims(
          subject: 'user-1',
          notBefore: now.add(const Duration(minutes: 5)),
        ),
      );

      final verifier = JwtVerifier(
        keys: <JwtKey>[key],
        leeway: Duration.zero,
        clock: () => now,
      );

      expect(_failureOf(verifier, token), 'token_not_yet_valid');
    });

    test('refuses a token of another issuer', () {
      final token = _token(
        key,
        JwtClaims(subject: 'user-1', issuer: 'https://other.example.com'),
      );

      final verifier = JwtVerifier(
        keys: <JwtKey>[key],
        issuer: 'https://auth.example.com',
      );

      expect(_failureOf(verifier, token), 'issuer_mismatch');
    });

    test('refuses a token meant for another service', () {
      final token = _token(
        key,
        JwtClaims(subject: 'user-1', audience: const <String>['billing']),
      );

      final verifier = JwtVerifier(
        keys: <JwtKey>[key],
        audience: const <String>['users'],
      );

      expect(_failureOf(verifier, token), 'audience_mismatch');
    });

    test('refuses a token without an algorithm', () {
      final token = _tokenWithHeader(
        key,
        JwtClaims(subject: 'user-1'),
        <String, Object?>{'typ': 'JWT'},
      );

      expect(
        _failureOf(JwtVerifier(keys: <JwtKey>[key]), token),
        'token_malformed',
      );
    });

    test('refuses a token that asks for an algorithm it does not know', () {
      final token = _tokenWithHeader(
        key,
        JwtClaims(subject: 'user-1'),
        <String, Object?>{'alg': 'none', 'typ': 'JWT'},
      );

      expect(
        _failureOf(JwtVerifier(keys: <JwtKey>[key]), token),
        'algorithm_unsupported',
      );
    });

    test('refuses a token that asks for another algorithm than the key', () {
      final token = _tokenWithHeader(
        key,
        JwtClaims(subject: 'user-1'),
        <String, Object?>{'alg': 'HS512', 'typ': 'JWT'},
      );

      expect(
        _failureOf(JwtVerifier(keys: <JwtKey>[key]), token),
        'algorithm_mismatch',
      );
    });

    test('refuses a token that is not a token', () {
      expect(
        _failureOf(JwtVerifier(keys: <JwtKey>[key]), 'not-a-token'),
        'token_malformed',
      );
    });

    test('verifies a token with the key of its kid', () {
      final oldKey = HmacJwtKey(
        utf8.encode('the old secret'),
        kid: 'old',
      );
      final newKey = HmacJwtKey(
        utf8.encode('the new secret'),
        kid: 'new',
      );

      final token = _token(newKey, JwtClaims(subject: 'user-1'));
      final verifier = JwtVerifier(keys: <JwtKey>[oldKey, newKey]);

      expect(verifier.verify(token).subject, 'user-1');
    });

    test('refuses a token of an unknown kid', () {
      final oldKey = HmacJwtKey(
        utf8.encode('the old secret'),
        kid: 'old',
      );
      final token = _token(
        HmacJwtKey(utf8.encode('the new secret'), kid: 'new'),
        JwtClaims(subject: 'user-1'),
      );

      expect(
        _failureOf(JwtVerifier(keys: <JwtKey>[oldKey]), token),
        'key_not_found',
      );
    });

    test('refuses a token signed with another secret', () {
      final other = HmacJwtKey(utf8.encode('the secret of another service'));
      final token = _token(other, JwtClaims(subject: 'user-1'));

      expect(
        _failureOf(JwtVerifier(keys: <JwtKey>[key]), token),
        'signature_invalid',
      );
    });
  });

  group('RSA', () {
    test('signs a token and verifies it with RS256', () {
      final keys = _rsaKeys();
      final key = RsaJwtKey.signing(keys.privateKey, kid: 'rsa-1');

      final token = _token(key, JwtClaims(subject: 'user-1'));

      final verifier = JwtVerifier(
        keys: <JwtKey>[
          RsaJwtKey(publicKey: keys.publicKey, kid: 'rsa-1'),
        ],
      );
      expect(verifier.verify(token).subject, 'user-1');
    });

    test('refuses a token signed with another key', () {
      final keys = _rsaKeys();
      final other = _rsaKeys();
      final token = _token(
        RsaJwtKey.signing(other.privateKey),
        JwtClaims(subject: 'user-1'),
      );

      final verifier = JwtVerifier(
        keys: <JwtKey>[RsaJwtKey(publicKey: keys.publicKey)],
      );

      expect(_failureOf(verifier, token), 'signature_invalid');
    });
  });

  group('ECDSA', () {
    test('signs a token and verifies it with ES256', () {
      final keys = _ecKeys();
      final key = EcJwtKey.signing(keys.privateKey, kid: 'ec-1');

      final token = _token(key, JwtClaims(subject: 'user-1'));

      final verifier = JwtVerifier(
        keys: <JwtKey>[
          EcJwtKey(publicKey: keys.publicKey, kid: 'ec-1'),
        ],
      );
      expect(verifier.verify(token).subject, 'user-1');
    });

    test('the signature of ES256 has the size of the curve', () {
      final keys = _ecKeys();
      final key = EcJwtKey.signing(keys.privateKey);

      final token = _token(key, JwtClaims(subject: 'user-1'));
      final signature = token.split('.')[2];

      // Two halves of 32 bytes each.
      expect(base64Url.decode(base64Url.normalize(signature)).length, 64);
    });
  });

  group('ApiKeyGuard', () {
    test('verifies a key it knows', () {
      final plain = newApiKey();
      final guard = ApiKeyGuard.fromPlain(<String>[plain]);

      final key = guard.verify(plain);

      expect(key, isNotNull);
      expect(key!.id, isNotEmpty);
    });

    test('refuses a key it does not know', () {
      final guard = ApiKeyGuard.fromPlain(<String>[newApiKey()]);

      expect(guard.verify(newApiKey()), isNull);
    });

    test('refuses an empty key', () {
      final guard = ApiKeyGuard.fromPlain(<String>[newApiKey()]);

      expect(guard.verify(''), isNull);
      expect(guard.verify(null), isNull);
    });

    test('keeps the hash of the key, not the key itself', () {
      final plain = newApiKey();
      final guard = ApiKeyGuard.fromPlain(<String>[plain]);

      expect(guard.length, 1);
      expect(hashApiKey(plain), isNot(plain));
      expect(guard.verify(plain)?.hash, hashApiKey(plain));
    });

    test('tells the scopes of a key', () {
      final plain = newApiKey();
      final guard = ApiKeyGuard(<ApiKey>[
        ApiKey(
          id: 'key-1',
          hash: hashApiKey(plain),
          scopes: const <String>['users:read'],
        ),
      ]);

      final key = guard.verify(plain);

      expect(key!.allows('users:read'), isTrue);
      expect(key.allows('users:write'), isFalse);
    });
  });

  group('jwtMiddleware', () {
    final key = HmacJwtKey(utf8.encode('a secret of the service'));

    test('leaves the caller in the request', () async {
      final token = _token(
        key,
        JwtClaims(
          subject: 'user-1',
          claims: <String, Object?>{'scope': 'users:read'},
        ),
      );
      final middleware = jwtMiddleware(JwtVerifier(keys: <JwtKey>[key]));
      final request = _request(
        'GET',
        '/me',
        headers: <String, String>{'authorization': 'Bearer $token'},
      );

      await middleware(request, () async => _ok());

      expect(request.principal?.id, 'user-1');
      expect(request.principal?.hasScope('users:read'), isTrue);
    });

    test('refuses a request without a token', () async {
      final middleware = jwtMiddleware(JwtVerifier(keys: <JwtKey>[key]));
      final request = _request('GET', '/me');

      await expectLater(
        middleware(request, () async => _ok()),
        throwsA(
          isA<HttpException>()
              .having((error) => error.status, 'status', 401)
              .having((error) => error.code, 'code', 'no_token'),
        ),
      );
    });

    test('refuses a request with a token of another service', () async {
      final token = _token(
        HmacJwtKey(utf8.encode('the secret of another service')),
        JwtClaims(subject: 'user-1'),
      );
      final middleware = jwtMiddleware(JwtVerifier(keys: <JwtKey>[key]));
      final request = _request(
        'GET',
        '/me',
        headers: <String, String>{'authorization': 'Bearer $token'},
      );

      await expectLater(
        middleware(request, () async => _ok()),
        throwsA(isA<HttpException>()),
      );
    });

    test('lets the request through when the token is not required', () async {
      final middleware = jwtMiddleware(
        JwtVerifier(keys: <JwtKey>[key]),
        required: false,
      );
      final request = _request('GET', '/me');

      final response = await middleware(request, () async => _ok());

      expect(response.status, 200);
      expect(request.principal, isNull);
    });
  });

  group('apiKeyMiddleware', () {
    test('leaves the key and the caller in the request', () async {
      final plain = newApiKey();
      final guard = ApiKeyGuard(<ApiKey>[
        ApiKey(
          id: 'key-1',
          hash: hashApiKey(plain),
          scopes: const <String>['users:read'],
        ),
      ]);
      final middleware = apiKeyMiddleware(guard);
      final request = _request(
        'GET',
        '/me',
        headers: <String, String>{'x-api-key': plain},
      );

      await middleware(request, () async => _ok());

      expect(request.apiKey?.id, 'key-1');
      expect(request.principal?.kind, PrincipalKind.apiKey);
      expect(request.principal?.id, 'key-1');
    });

    test('refuses a request without a key', () async {
      final guard = ApiKeyGuard.fromPlain(<String>[newApiKey()]);
      final middleware = apiKeyMiddleware(guard);

      await expectLater(
        middleware(_request('GET', '/me'), () async => _ok()),
        throwsA(
          isA<HttpException>()
              .having((error) => error.status, 'status', 401)
              .having((error) => error.code, 'code', 'invalid_api_key'),
        ),
      );
    });
  });

  group('requireScope', () {
    test('refuses a caller without the scope', () async {
      final middleware = requireScope('users:write');
      final request = _request('GET', '/me')
        ..principal =
            const Principal(id: 'user-1', scopes: <String>['users:read']);

      await expectLater(
        middleware(request, () async => _ok()),
        throwsA(
          isA<HttpException>()
              .having((error) => error.status, 'status', 403)
              .having((error) => error.code, 'code', 'insufficient_scope'),
        ),
      );
    });

    test('lets a caller with the scope through', () async {
      final middleware = requireScope('users:write');
      final request = _request('GET', '/me')
        ..principal =
            const Principal(id: 'user-1', scopes: <String>['users:write']);

      final response = await middleware(request, () async => _ok());

      expect(response.status, 200);
    });
  });
}
