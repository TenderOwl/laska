import 'package:auth_service_example/app.dart';
import 'package:auth_service_example/keys.dart';
import 'package:laska_core/laska_core.dart';
import 'package:laska_test/laska_test.dart';
import 'package:test/test.dart';

void main() {
  group('the authentication of the callers', () {
    late ServiceKeys keys;
    late TestClient client;

    setUp(() async {
      keys = ServiceKeys.development();
      client = testClient(await buildApp(keys: keys));
    });

    test('a public route answers without a caller', () async {
      final response = await client.get('/public');

      response.expectStatus(200);
    });

    test('a protected route refuses a caller without a token', () async {
      final response = await client.get('/me');

      response.expectStatus(401);
      expect(response.jsonObject['code'], 'no_token');
      expect(response.headers['www-authenticate'], 'Bearer error="no_token"');
    });

    test(
      'the token of the login opens the route and names the caller',
      () async {
        final login = await client.post(
          '/login',
          body: <String, Object?>{'name': 'ada', 'password': 'lovelace'},
        );

        login.expectStatus(200);
        final token = login.jsonObject['token']! as String;

        final response = await client.get(
          '/me',
          headers: <String, String>{'authorization': 'Bearer $token'},
        );

        response.expectStatus(200);
        expect(response.jsonObject['id'], 'ada');
        expect(response.jsonObject['scopes'], <String>['read']);
      },
    );

    test('a wrong name or password is refused', () async {
      final response = await client.post(
        '/login',
        body: <String, Object?>{'name': 'ada', 'password': 'wrong'},
      );

      response.expectStatus(401);
      expect(response.jsonObject['code'], 'invalid_credentials');
    });

    test('a token of another service is refused', () async {
      final token = _token(keys, audience: 'another-service');

      final response = await client.get(
        '/me',
        headers: <String, String>{'authorization': 'Bearer $token'},
      );

      response.expectStatus(401);
      expect(response.jsonObject['code'], 'audience_mismatch');
    });

    test('a token of another issuer is refused', () async {
      final token = _token(keys, issuer: 'https://another.issuer');

      final response = await client.get(
        '/me',
        headers: <String, String>{'authorization': 'Bearer $token'},
      );

      response.expectStatus(401);
      expect(response.jsonObject['code'], 'issuer_mismatch');
    });

    test('an expired token is refused', () async {
      final token = _token(
        keys,
        expiresAt: DateTime.now().subtract(const Duration(hours: 1)),
      );

      final response = await client.get(
        '/me',
        headers: <String, String>{'authorization': 'Bearer $token'},
      );

      response.expectStatus(401);
      expect(response.jsonObject['code'], 'token_expired');
    });

    test('a token signed with another key is refused', () async {
      final other = ServiceKeys.development();
      final token = _token(other);

      final response = await client.get(
        '/me',
        headers: <String, String>{'authorization': 'Bearer $token'},
      );

      response.expectStatus(401);
    });

    test('a route with a scope refuses a caller without it', () async {
      final token = _token(keys, scopes: const <String>['read']);

      final response = await client.get(
        '/admin',
        headers: <String, String>{'authorization': 'Bearer $token'},
      );

      response.expectStatus(403);
      expect(response.jsonObject['code'], 'insufficient_scope');
    });

    test('a token with the scope opens the route', () async {
      final token = _token(keys, scopes: const <String>['read', 'admin']);

      final response = await client.get(
        '/admin',
        headers: <String, String>{'authorization': 'Bearer $token'},
      );

      response.expectStatus(200);
    });

    test('the API key of a machine opens the machine route', () async {
      final response = await client.get(
        '/machine',
        headers: <String, String>{'x-api-key': 'machine-secret'},
      );

      response.expectStatus(200);
      expect(response.jsonObject['client'], 'reporting');
    });

    test('a wrong API key is refused', () async {
      final response = await client.get(
        '/machine',
        headers: <String, String>{'x-api-key': 'wrong'},
      );

      response.expectStatus(401);
      expect(response.jsonObject['code'], 'invalid_api_key');
    });

    test('the session of a browser opens the session route', () async {
      final login = await client.post(
        '/session',
        body: <String, Object?>{'name': 'ada', 'password': 'lovelace'},
      );

      login.expectStatus(201);
      final cookie = login.headers['set-cookie']!;

      final response = await client.get(
        '/session',
        headers: <String, String>{'cookie': cookie.split(';').first},
      );

      response.expectStatus(200);
      expect(response.jsonObject['user_id'], 'ada');
    });

    test('a request without a session is refused', () async {
      final response = await client.get('/session');

      response.expectStatus(401);
      expect(response.jsonObject['code'], 'no_session');
    });

    test('a caller that floods the service gets a 429', () async {
      final limited = testClient(
        await buildApp(
          keys: keys,
          limiter: RateLimiter(limit: 1, window: const Duration(minutes: 1)),
        ),
      );

      await limited.get('/public');
      final response = await limited.get('/public');

      response.expectStatus(429);
      expect(response.jsonObject['code'], 'rate_limited');
      expect(response.headers['retry-after'], isNotNull);
    });
  });
}

/// Signs a token for the test.
String _token(
  ServiceKeys keys, {
  List<String> scopes = const <String>['read'],
  String audience = serviceAudience,
  String issuer = serviceIssuer,
  DateTime? expiresAt,
}) {
  return keys.signer.sign(
    JwtClaims(
      issuer: issuer,
      audience: <String>[audience],
      subject: 'ada',
      expiresAt: expiresAt ?? DateTime.now().add(const Duration(hours: 1)),
      claims: <String, Object?>{'scope': scopes.join(' ')},
    ),
  );
}
