import 'package:laska_core/laska_core.dart';
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

/// The cookie header that carries the session [id].
String _cookie(String id) => 'laska_session=$id';

void main() {
  group('the session store', () {
    test('keeps the session it is given', () async {
      final store = MemorySessionStore();
      final session = await startSession(store, data: <String, Object?>{
        'user_id': 'user-1',
      });

      final found = await store.find(session.id);

      expect(found, isNotNull);
      expect(found!.data['user_id'], 'user-1');
      expect(store.length, 1);
    });

    test('drops the oldest session when it is full', () async {
      final store = MemorySessionStore(maxSessions: 2);

      final first = await startSession(store);
      final second = await startSession(store);
      final third = await startSession(store);

      expect(await store.find(first.id), isNull);
      expect(await store.find(second.id), isNotNull);
      expect(await store.find(third.id), isNotNull);
    });

    test('the id of a session is long and random', () {
      final first = newSessionId();
      final second = newSessionId();

      expect(first.length, greaterThan(30));
      expect(first, isNot(second));
    });
  });

  group('the session of the caller', () {
    test('the id of the session is replaced when the privileges change',
        () async {
      final store = MemorySessionStore();
      final session = await startSession(store, data: <String, Object?>{
        'user_id': 'user-1',
      });

      final fresh = await regenerateSession(store, session);

      expect(fresh.id, isNot(session.id));
      expect(fresh.data['user_id'], 'user-1');

      // The old id is dead, so an id that leaked before the login is of no
      // use to the one who leaked it.
      expect(await store.find(session.id), isNull);
      expect(await store.find(fresh.id), isNotNull);
    });

    test('the session is gone after it is destroyed', () async {
      final store = MemorySessionStore();
      final session = await startSession(store);

      await destroySession(store, session);

      expect(await store.find(session.id), isNull);
    });
  });

  group('the cookie of the session', () {
    test('holds the id of the session and the flags of safety', () {
      final cookie = renderSessionCookie(
        'abc-123',
        expires: DateTime.utc(2026, 1, 1, 12),
      );

      expect(cookie, contains('laska_session=abc-123'));
      expect(cookie, contains('HttpOnly'));
      expect(cookie, contains('Secure'));
      expect(cookie, contains('SameSite=Lax'));
      expect(cookie, contains('Expires=Thu, 01 Jan 2026 12:00:00 GMT'));
    });

    test('is read back out of the header of the request', () {
      final header = 'theme=dark; laska_session=abc-123; other=1';

      expect(readCookie(header, sessionCookieName), 'abc-123');
      expect(readCookie(header, 'theme'), 'dark');
      expect(readCookie(header, 'missing'), isNull);
      expect(readCookie(null, sessionCookieName), isNull);
    });

    test('the cookie that ends the session expires at once', () {
      final cookie = renderClearedSessionCookie();

      expect(cookie, contains('Max-Age=0'));
      expect(cookie, contains('Expires=Thu, 01 Jan 1970 00:00:00 GMT'));
      expect(cookie, contains('HttpOnly'));
    });
  });

  group('sessionMiddleware', () {
    test('puts the session of the caller in the request', () async {
      final store = MemorySessionStore();
      final session = await startSession(store, data: <String, Object?>{
        'user_id': 'user-1',
      });
      final middleware = sessionMiddleware(store);
      final request = _request(
        'GET',
        '/me',
        headers: <String, String>{'cookie': _cookie(session.id)},
      );

      await middleware(request, () async => _ok());

      expect(request.session?.id, session.id);
      expect(request.principal?.id, 'user-1');
    });

    test('lets a request without a session through', () async {
      final store = MemorySessionStore();
      final middleware = sessionMiddleware(store);
      final request = _request('GET', '/me');

      final response = await middleware(request, () async => _ok());

      expect(response.status, 200);
      expect(request.session, isNull);
    });

    test('refuses a request without a session when it is required', () async {
      final store = MemorySessionStore();
      final middleware = sessionMiddleware(store, required: true);

      await expectLater(
        middleware(_request('GET', '/me'), () async => _ok()),
        throwsA(
          isA<HttpException>()
              .having((error) => error.status, 'status', 401)
              .having((error) => error.code, 'code', 'no_session'),
        ),
      );
    });

    test('refuses a session that has expired', () async {
      final store = MemorySessionStore();
      final session = await startSession(
        store,
        lifetime: const Duration(seconds: -1),
      );
      final middleware = sessionMiddleware(store, required: true);
      final request = _request(
        'GET',
        '/me',
        headers: <String, String>{'cookie': _cookie(session.id)},
      );

      await expectLater(
        middleware(request, () async => _ok()),
        throwsA(
          isA<HttpException>()
              .having((error) => error.code, 'code', 'invalid_session'),
        ),
      );

      // The expired session is removed from the store.
      expect(await store.find(session.id), isNull);
    });
  });

  group('the rate limiter', () {
    test('lets the calls of a key through until the limit', () {
      final limiter = RateLimiter(limit: 3, window: const Duration(minutes: 1));

      expect(limiter.allow('a'), isTrue);
      expect(limiter.allow('a'), isTrue);
      expect(limiter.allow('a'), isTrue);
      expect(limiter.allow('a'), isFalse);
    });

    test('the keys do not share their tokens', () {
      final limiter = RateLimiter(limit: 1, window: const Duration(minutes: 1));

      expect(limiter.allow('a'), isTrue);
      expect(limiter.allow('b'), isTrue);
      expect(limiter.allow('a'), isFalse);
    });

    test('the bucket is filled again with the time', () {
      var now = DateTime.utc(2026, 1, 1, 12);
      final limiter = RateLimiter(
        limit: 1,
        window: const Duration(minutes: 1),
        clock: () => now,
      );

      expect(limiter.allow('a'), isTrue);
      expect(limiter.allow('a'), isFalse);

      now = now.add(const Duration(minutes: 1));
      expect(limiter.allow('a'), isTrue);
    });

    test('the limiter does not grow without a bound', () {
      final limiter = RateLimiter(limit: 10, maxKeys: 3);

      for (var index = 0; index < 100; index++) {
        limiter.allow('key-$index');
      }

      expect(limiter.keys, lessThanOrEqualTo(3));
    });

    test('the bucket of a key may be forgotten', () {
      final limiter = RateLimiter(limit: 1);

      expect(limiter.allow('a'), isTrue);
      expect(limiter.allow('a'), isFalse);

      limiter.forget('a');

      expect(limiter.allow('a'), isTrue);
    });
  });

  group('rateLimitMiddleware', () {
    test('refuses the caller that makes too many calls', () async {
      final limiter = RateLimiter(limit: 2, window: const Duration(minutes: 1));
      final middleware = rateLimitMiddleware(limiter);

      await middleware(_request('GET', '/'), () async => _ok());
      await middleware(_request('GET', '/'), () async => _ok());

      await expectLater(
        middleware(_request('GET', '/'), () async => _ok()),
        throwsA(
          isA<HttpException>()
              .having((error) => error.status, 'status', 429)
              .having((error) => error.code, 'code', 'rate_limited')
              .having(
                (error) => error.headers?['retry-after'],
                'retry-after',
                isNotNull,
              ),
        ),
      );
    });

    test('the limit follows the caller, not the connection', () async {
      final limiter = RateLimiter(limit: 1, window: const Duration(minutes: 1));
      final middleware = rateLimitMiddleware(limiter);

      final first = _request('GET', '/')
        ..principal = const Principal(id: 'user-1');
      final second = _request('GET', '/')
        ..principal = const Principal(id: 'user-2');

      await middleware(first, () async => _ok());
      await middleware(second, () async => _ok());

      await expectLater(
        middleware(first, () async => _ok()),
        throwsA(isA<HttpException>()),
      );
    });

    test('a caller nobody knows is limited by its address', () async {
      final limiter = RateLimiter(limit: 1, window: const Duration(minutes: 1));
      final middleware = rateLimitMiddleware(limiter);

      final first = _request(
        'GET',
        '/',
        headers: <String, String>{'x-forwarded-for': '203.0.113.7, 10.0.0.1'},
      );
      final second = _request(
        'GET',
        '/',
        headers: <String, String>{'x-forwarded-for': '203.0.113.8'},
      );

      await middleware(first, () async => _ok());
      await middleware(second, () async => _ok());

      await expectLater(
        middleware(first, () async => _ok()),
        throwsA(isA<HttpException>()),
      );
    });
  });
}
