import 'dart:io';

import 'package:laska_core/laska_core.dart';
import 'package:test/test.dart';

Response _ok(Context ctx) => ctx.text('ok');

Future<HttpClientResponse> _get(HttpServer server, String path) async {
  final client = HttpClient();
  final request =
      await client.getUrl(Uri.parse('http://127.0.0.1:${server.port}$path'));
  final response = await request.close();
  await response.drain<void>();
  client.close();
  return response;
}

void main() {
  group('Router', () {
    test('matches a static route', () {
      final router = Router()..add('GET', '/users', _ok);

      final match = router.lookup('GET', '/users');

      expect(match, isNotNull);
      expect(match!.route.method, 'GET');
      expect(match.params, isEmpty);
    });

    test('matches a route with parameters', () {
      final router = Router()..add('GET', '/users/:id', _ok);

      final match = router.lookup('GET', '/users/42');

      expect(match, isNotNull);
      expect(match!.params, <String, String>{'id': '42'});
    });

    test('prefers a static route over a parameter route', () {
      final router = Router()
        ..add('GET', '/users/:id', _ok)
        ..add('GET', '/users/me', _ok);

      final match = router.lookup('GET', '/users/me');

      expect(match, isNotNull);
      expect(match!.params, isEmpty);
    });

    test('does not match a different method', () {
      final router = Router()..add('GET', '/users', _ok);

      expect(router.lookup('POST', '/users'), isNull);
      expect(router.allowedMethods('/users'), <String>{'GET'});
    });

    test('matches a wildcard', () {
      final router = Router()..add('GET', '/files/*', _ok);

      final match = router.lookup('GET', '/files/a/b/c.txt');

      expect(match, isNotNull);
    });

    test('ignores a trailing slash', () {
      final router = Router()..add('GET', '/users', _ok);

      expect(router.lookup('GET', '/users/'), isNotNull);
    });
  });

  group('Laska', () {
    test('groups add a prefix', () {
      final app = Laska();
      app.group('/admin', (group) {
        group.get('/users', _ok);
      });

      final match = app.router.lookup('GET', '/admin/users');

      expect(match, isNotNull);
    });

    test('group middleware runs before the route handler', () async {
      final calls = <String>[];
      final app = Laska();

      app.group(
        '/admin',
        (group) {
          group.get(
            '/users',
            (ctx) async {
              calls.add('handler');
              return ctx.text('ok');
            },
          );
        },
        middleware: [
          (request, next) async {
            calls.add('middleware');
            return next();
          },
        ],
      );

      final server = await serve(app, port: 0);
      final response = await _get(server, '/admin/users');
      await server.close(force: true);

      expect(response.statusCode, 200);
      expect(calls, <String>['middleware', 'handler']);
    });
  });
}
