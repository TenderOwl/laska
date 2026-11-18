import 'dart:convert';

import 'package:laska_core/laska_core.dart';
import 'package:test/test.dart';

/// The document of the key set of [keys].
String _document(List<JwtKey> keys) => jsonEncode(jwksDocument(keys));

/// The key of the id [kid] in the set of [keys].
JwtKey _keyOf(List<JwtKey> keys, String kid) =>
    keys.firstWhere((key) => key.kid == kid);

void main() {
  group('jwksDocument and parseJwks', () {
    test('the public key of RSA verifies the token of the private key', () {
      final key = generateRsaKey(kid: 'rsa-1', bits: 1024);
      final token = JwtSigner(key).sign(JwtClaims(subject: 'user-1'));

      final parsed = parseJwks(_document(<JwtKey>[key]));

      expect(parsed, hasLength(1));
      expect(parsed.first.kid, 'rsa-1');
      expect(parsed.first.algorithm, JwtAlgorithm.rs256);

      final verifier = JwtVerifier(keys: parsed);
      expect(verifier.verify(token).subject, 'user-1');
    });

    test('the public key of the curve verifies the token', () {
      final key = generateEcKey(kid: 'ec-1');
      final token = JwtSigner(key).sign(JwtClaims(subject: 'user-1'));

      final parsed = parseJwks(_document(<JwtKey>[key]));

      expect(parsed, hasLength(1));
      expect(parsed.first.kid, 'ec-1');

      final verifier = JwtVerifier(keys: parsed);
      expect(verifier.verify(token).subject, 'user-1');
    });

    test('the private key of the document may sign again', () {
      final key = generateEcKey(kid: 'ec-1');

      final document = jsonEncode(key.toJwk(includeSecret: true));
      final parsed = keyFromJwk(jsonDecode(document) as Map<String, Object?>);

      expect(parsed.canSign, isTrue);

      final token = JwtSigner(parsed).sign(JwtClaims(subject: 'user-1'));
      final verifier = JwtVerifier(keys: <JwtKey>[key]);
      expect(verifier.verify(token).subject, 'user-1');
    });

    test('the document holds no secret of the public keys', () {
      final key = generateEcKey(kid: 'ec-1');

      final document = key.toJwk();

      expect(document.containsKey('d'), isFalse);
      expect(document['kty'], 'EC');
      expect(document['crv'], 'P-256');
    });

    test('the secret of an HMAC key is only in the document on request', () {
      final key = generateHmacKey(kid: 'hmac-1');

      expect(key.toJwk().containsKey('k'), isFalse);
      expect(key.toJwk(includeSecret: true).containsKey('k'), isTrue);
    });

    test('a document that is not a key set is refused', () {
      expect(
        () => parseJwks('not json'),
        throwsA(isA<JwksException>()),
      );
      expect(
        () => parseJwks('{"no":"keys"}'),
        throwsA(isA<JwksException>()),
      );
    });

    test('a key of an unknown type is refused', () {
      expect(
        () => parseJwks('{"keys":[{"kty":"OKP","crv":"Ed25519"}]}'),
        throwsA(isA<JwksException>()),
      );
    });
  });

  group('JwksCache', () {
    test('fetches the set once and keeps it', () async {
      final key = generateEcKey(kid: 'ec-1');
      var fetches = 0;

      final cache = JwksCache(
        uri: Uri.parse('https://auth.example.com/.well-known/jwks.json'),
        fetcher: (uri) async {
          fetches++;
          return _document(<JwtKey>[key]);
        },
      );

      await cache.resolve('ec-1');
      await cache.resolve('ec-1');

      expect(fetches, 1);
      expect(cache.keys, hasLength(1));
    });

    test('fetches the set again when the key of the token is unknown',
        () async {
      final oldKey = generateEcKey(kid: 'ec-1');
      final newKey = generateEcKey(kid: 'ec-2');
      var fetches = 0;

      final cache = JwksCache(
        uri: Uri.parse('https://auth.example.com/.well-known/jwks.json'),
        minRefreshInterval: Duration.zero,
        fetcher: (uri) async {
          fetches++;
          // The service rotates its keys: the set holds the new key from the
          // second fetch on.
          return _document(<JwtKey>[fetches == 1 ? oldKey : newKey]);
        },
      );

      expect((await cache.resolve('ec-1')), hasLength(1));
      expect(fetches, 1);

      // The token names the key the service started to use after the cache
      // fetched the set.
      final found = await cache.resolve('ec-2');

      expect(found, hasLength(1));
      expect(found.first.kid, 'ec-2');
      expect(fetches, 2);
    });

    test('does not fetch the set twice in a moment', () async {
      final key = generateEcKey(kid: 'ec-1');
      var fetches = 0;

      final cache = JwksCache(
        uri: Uri.parse('https://auth.example.com/.well-known/jwks.json'),
        minRefreshInterval: const Duration(minutes: 1),
        fetcher: (uri) async {
          fetches++;
          return _document(<JwtKey>[key]);
        },
      );

      await cache.resolve('ec-1');
      await cache.resolve('unknown');
      await cache.resolve('another-unknown');

      expect(fetches, 1);
    });

    test('the verifier of the cache accepts the token of the new key',
        () async {
      final oldKey = generateEcKey(kid: 'ec-1');
      final newKey = generateEcKey(kid: 'ec-2');
      var fetches = 0;

      final cache = JwksCache(
        uri: Uri.parse('https://auth.example.com/.well-known/jwks.json'),
        minRefreshInterval: Duration.zero,
        fetcher: (uri) async {
          fetches++;
          return _document(<JwtKey>[fetches == 1 ? oldKey : newKey]);
        },
      );
      final verifier = JwtVerifier.withSource(cache);

      final token = JwtSigner(newKey).sign(JwtClaims(subject: 'user-1'));
      final jwt = await verifier.verifyAsync(token);

      expect(jwt.subject, 'user-1');
    });

    test('the verifier of the cache refuses the token of an unknown key',
        () async {
      final key = generateEcKey(kid: 'ec-1');
      final other = generateEcKey(kid: 'ec-2');

      final cache = JwksCache(
        uri: Uri.parse('https://auth.example.com/.well-known/jwks.json'),
        minRefreshInterval: Duration.zero,
        fetcher: (uri) async => _document(<JwtKey>[key]),
      );
      final verifier = JwtVerifier.withSource(cache);

      final token = JwtSigner(other).sign(JwtClaims(subject: 'user-1'));

      await expectLater(
        verifier.verifyAsync(token),
        throwsA(
          isA<JwtException>()
              .having((error) => error.code, 'code', 'key_not_found'),
        ),
      );
    });
  });

  group('the generated keys', () {
    test('a key of RSA signs a token the service may verify', () {
      final key = generateRsaKey(kid: 'rsa-1', bits: 1024);
      final token = JwtSigner(key).sign(JwtClaims(subject: 'user-1'));

      final parsed = parseJwks(_document(<JwtKey>[key]));
      final verifier = JwtVerifier(keys: parsed);

      expect(verifier.verify(token).subject, 'user-1');
    });

    test('the id of a key is not empty and is not repeated', () {
      final first = newKeyId();
      final second = newKeyId();

      expect(first, isNotEmpty);
      expect(first, isNot(second));
    });

    test('the keys of a rotation live beside each other', () {
      final oldKey = generateEcKey(kid: 'ec-1');
      final newKey = generateEcKey(kid: 'ec-2');

      final verifier = JwtVerifier(keys: <JwtKey>[oldKey, newKey]);

      final oldToken = JwtSigner(oldKey).sign(JwtClaims(subject: 'user-1'));
      final newToken = JwtSigner(newKey).sign(JwtClaims(subject: 'user-2'));

      expect(verifier.verify(oldToken).subject, 'user-1');
      expect(verifier.verify(newToken).subject, 'user-2');
      expect(_keyOf(<JwtKey>[oldKey, newKey], 'ec-2').kid, 'ec-2');
    });
  });
}
