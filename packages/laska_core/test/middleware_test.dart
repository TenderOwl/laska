import 'dart:convert';

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

Response _ok(Context ctx) => ctx.text('ok');

void main() {
  group('requestIdMiddleware', () {
    test('generates an id when the client sends none', () async {
      final middleware = requestIdMiddleware();

      final response = await middleware(_request('GET', '/'), () async {
        return _ok(_context());
      });

      expect(response.headers['x-request-id'], isNotNull);
    });

    test('keeps the id sent by the client', () async {
      final middleware = requestIdMiddleware();
      final request = _request(
        'GET',
        '/',
        headers: <String, String>{'x-request-id': 'abc-123'},
      );

      final response = await middleware(request, () async => _ok(_context()));

      expect(response.headers['x-request-id'], 'abc-123');
      expect(request.id, 'abc-123');
    });

    test('uses a custom header name', () async {
      final middleware = requestIdMiddleware(header: 'x-trace-id');
      final request = _request(
        'GET',
        '/',
        headers: <String, String>{'x-trace-id': 'trace-1'},
      );

      final response = await middleware(request, () async => _ok(_context()));

      expect(response.headers['x-trace-id'], 'trace-1');
    });
  });

  group('loggingMiddleware', () {
    test('writes one record per request', () async {
      final lines = <String>[];
      final logger = Logger(sink: lines.add);
      final middleware = loggingMiddleware(logger);
      final request = _request('GET', '/users');

      await middleware(request, () async => _ok(_context()));

      expect(lines, hasLength(1));
      final record = jsonDecode(lines.single) as Map<String, Object?>;
      expect(record['message'], 'request');
      expect(record['method'], 'GET');
      expect(record['path'], '/users');
      expect(record['status'], 200);
    });

    test('writes an error record when the handler fails', () async {
      final lines = <String>[];
      final logger = Logger(sink: lines.add);
      final middleware = loggingMiddleware(logger);

      await expectLater(
        middleware(_request('GET', '/users'), () async {
          throw StateError('boom');
        }),
        throwsStateError,
      );

      final record = jsonDecode(lines.single) as Map<String, Object?>;
      expect(record['level'], 'error');
      expect(record['message'], 'request failed');
    });
  });

  group('corsMiddleware', () {
    test('adds the allow origin header', () async {
      final middleware = corsMiddleware();
      final request = _request(
        'GET',
        '/',
        headers: <String, String>{'origin': 'https://app.example'},
      );

      final response = await middleware(request, () async => _ok(_context()));

      expect(response.headers['access-control-allow-origin'], '*');
    });

    test('answers a preflight request', () async {
      final middleware = corsMiddleware();
      final request = _request(
        'OPTIONS',
        '/',
        headers: <String, String>{
          'origin': 'https://app.example',
          'access-control-request-method': 'POST',
        },
      );

      final response = await middleware(request, () async => _ok(_context()));

      expect(response.status, 204);
      expect(response.headers['access-control-allow-origin'], '*');
    });

    test('does not answer a request without an origin', () async {
      final middleware = corsMiddleware();

      final response = await middleware(
        _request('GET', '/'),
        () async => _ok(_context()),
      );

      expect(
          response.headers.containsKey('access-control-allow-origin'), isFalse);
    });

    test('respects the list of allowed origins', () async {
      final middleware = corsMiddleware(
        const CorsOptions(allowedOrigins: <String>['https://app.example']),
      );
      final request = _request(
        'GET',
        '/',
        headers: <String, String>{'origin': 'https://other.example'},
      );

      final response = await middleware(request, () async => _ok(_context()));

      expect(
          response.headers.containsKey('access-control-allow-origin'), isFalse);
    });
  });

  group('securityHeadersMiddleware', () {
    test('adds the security headers', () async {
      final middleware = securityHeadersMiddleware();

      final response = await middleware(
        _request('GET', '/'),
        () async => _ok(_context()),
      );

      expect(response.headers['x-content-type-options'], 'nosniff');
      expect(response.headers['x-frame-options'], 'DENY');
      expect(response.headers['referrer-policy'], 'no-referrer');
    });

    test('accepts custom headers', () async {
      final middleware = securityHeadersMiddleware(
        headers: const <String, String>{'x-frame-options': 'SAMEORIGIN'},
      );

      final response = await middleware(
        _request('GET', '/'),
        () async => _ok(_context()),
      );

      expect(response.headers['x-frame-options'], 'SAMEORIGIN');
    });
  });
}

Context _context() => Context(
      Request(
        method: 'GET',
        path: '/',
        uri: '/',
        query: const <String, String>{},
        headers: const <String, String>{},
      ),
      Laska(),
    );
