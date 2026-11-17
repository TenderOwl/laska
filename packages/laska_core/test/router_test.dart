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
      expect(match!.params['*'], 'a/b/c.txt');
    });

    test('ignores a trailing slash', () {
      final router = Router()..add('GET', '/users', _ok);

      expect(router.lookup('GET', '/users/'), isNotNull);
    });
  });

  group('Router constraints', () {
    test('matches an integer parameter', () {
      final router = Router()..add('GET', '/orders/:id<int>', _ok);

      expect(router.lookup('GET', '/orders/42'), isNotNull);
      expect(router.lookup('GET', '/orders/abc'), isNull);
    });

    test('matches a float parameter', () {
      final router = Router()..add('GET', '/prices/:value<float>', _ok);

      expect(router.lookup('GET', '/prices/1.5'), isNotNull);
      expect(router.lookup('GET', '/prices/1'), isNotNull);
      expect(router.lookup('GET', '/prices/abc'), isNull);
    });

    test('matches a boolean parameter', () {
      final router = Router()..add('GET', '/flags/:value<bool>', _ok);

      expect(router.lookup('GET', '/flags/true'), isNotNull);
      expect(router.lookup('GET', '/flags/0'), isNotNull);
      expect(router.lookup('GET', '/flags/maybe'), isNull);
    });

    test('matches a uuid parameter', () {
      final router = Router()..add('GET', '/things/:id<uuid>', _ok);
      const uuid = '123e4567-e89b-12d3-a456-426614174000';

      expect(router.lookup('GET', '/things/$uuid'), isNotNull);
      expect(router.lookup('GET', '/things/nope'), isNull);
    });

    test('matches a slug parameter', () {
      final router = Router()..add('GET', '/posts/:slug<slug>', _ok);

      expect(router.lookup('GET', '/posts/hello-world'), isNotNull);
      expect(router.lookup('GET', '/posts/Hello World'), isNull);
    });

    test('matches a custom regular expression', () {
      final router = Router()..add('GET', '/codes/:code<^[A-Z]{3}\$>', _ok);

      expect(router.lookup('GET', '/codes/ABC'), isNotNull);
      expect(router.lookup('GET', '/codes/abc'), isNull);
    });

    test('prefers a constrained parameter over a plain one', () {
      final router = Router()
        ..add('GET', '/items/:id', _ok)
        ..add('GET', '/items/:id<int>', _ok);

      final match = router.lookup('GET', '/items/42');

      expect(match, isNotNull);
      expect(match!.route.path, '/items/:id<int>');
    });

    test('falls back to the plain parameter when the constraint fails', () {
      final router = Router()
        ..add('GET', '/items/:id', _ok)
        ..add('GET', '/items/:id<int>', _ok);

      final match = router.lookup('GET', '/items/abc');

      expect(match, isNotNull);
      expect(match!.route.path, '/items/:id');
      expect(match.params['id'], 'abc');
    });
  });

  group('Router optional parameters', () {
    test('matches the path without the optional segment', () {
      final router = Router()..add('GET', '/users/:id?', _ok);

      final match = router.lookup('GET', '/users');

      expect(match, isNotNull);
      expect(match!.params, isEmpty);
    });

    test('matches the path with the optional segment', () {
      final router = Router()..add('GET', '/users/:id?', _ok);

      final match = router.lookup('GET', '/users/42');

      expect(match, isNotNull);
      expect(match!.params['id'], '42');
    });
  });

  group('Router named routes', () {
    test('registers a route under a name', () {
      final router = Router()..add('GET', '/users/:id', _ok, name: 'user');

      expect(router.routeByName('user')?.path, '/users/:id');
    });

    test('rejects a duplicated name', () {
      final router = Router()..add('GET', '/users', _ok, name: 'user');

      expect(
        () => router.add('GET', '/people', _ok, name: 'user'),
        throwsArgumentError,
      );
    });

    test('builds a path from a name', () {
      final router = Router()..add('GET', '/users/:id', _ok, name: 'user');

      expect(router.urlFor('user', <String, String>{'id': '42'}), '/users/42');
    });

    test('encodes the parameters of a path', () {
      final router = Router()..add('GET', '/users/:id', _ok, name: 'user');

      expect(
        router.urlFor('user', <String, String>{'id': 'a b'}),
        '/users/a%20b',
      );
    });

    test('skips an optional parameter that is not given', () {
      final router = Router()..add('GET', '/users/:id?', _ok, name: 'user');

      expect(router.urlFor('user'), '/users');
    });

    test('throws when a parameter is missing', () {
      final router = Router()..add('GET', '/users/:id', _ok, name: 'user');

      expect(() => router.urlFor('user'), throwsA(isA<RouteNotFound>()));
    });

    test('throws when the name is unknown', () {
      final router = Router();

      expect(() => router.urlFor('nope'), throwsA(isA<RouteNotFound>()));
    });
  });

  group('Router table', () {
    test('renders the registered routes', () {
      final router = Router()
        ..add('GET', '/users', _ok, name: 'users')
        ..add('POST', '/users', _ok);

      final table = router.table();

      expect(table, contains('METHOD'));
      expect(table, contains('/users'));
      expect(table, contains('users'));
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

    test('builds a path from a named route', () {
      final app = Laska();
      app.get('/users/:id', _ok, name: 'user');

      expect(app.urlFor('user', <String, String>{'id': '42'}), '/users/42');
    });

    test('registers a route for every common method', () {
      final app = Laska()..any('/ping', _ok);

      expect(app.router.lookup('GET', '/ping'), isNotNull);
      expect(app.router.lookup('POST', '/ping'), isNotNull);
      expect(app.router.lookup('DELETE', '/ping'), isNotNull);
    });

    test('registers a named route for every common method', () {
      final app = Laska()..any('/ping', _ok, name: 'ping');

      expect(app.urlFor('ping'), '/ping');
      expect(app.router.lookup('POST', '/ping'), isNotNull);
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
