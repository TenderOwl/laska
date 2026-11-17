import 'package:laska_core/laska_core.dart';
import 'package:test/test.dart';

Request _request(
  String method,
  String path, {
  Map<String, String>? query,
  Map<String, String>? headers,
  String body = '',
}) {
  final uri = Uri.parse(path);
  return Request(
    method: method,
    path: uri.path,
    uri: path,
    query: query ?? uri.queryParameters,
    headers: headers ?? const <String, String>{},
    body: body,
  );
}

void main() {
  group('Dispatcher', () {
    test('calls the handler of the matching route', () async {
      final app = Laska();
      app.get('/users', (ctx) => ctx.json(<String, Object?>{'ok': true}));

      final response = await app.dispatcher.dispatch(_request('GET', '/users'));

      expect(response.status, 200);
      expect(response.jsonObject['ok'], isTrue);
    });

    test('passes the route parameters to the handler', () async {
      final app = Laska();
      app.get('/users/:id', (ctx) => ctx.text(ctx.params['id']!));

      final response =
          await app.dispatcher.dispatch(_request('GET', '/users/42'));

      expect(response.text, '42');
    });

    test('passes the query parameters to the handler', () async {
      final app = Laska();
      app.get('/search', (ctx) => ctx.text(ctx.query['q']!));

      final response =
          await app.dispatcher.dispatch(_request('GET', '/search?q=dart'));

      expect(response.text, 'dart');
    });

    test('answers 404 with a problem document', () async {
      final app = Laska();

      final response = await app.dispatcher.dispatch(_request('GET', '/nope'));

      expect(response.status, 404);
      expect(response.headers['content-type'],
          contains('application/problem+json'));
      expect(response.jsonObject['title'], 'Not Found');
      expect(response.jsonObject['status'], 404);
    });

    test('answers 405 with an Allow header', () async {
      final app = Laska();
      app.get('/users', (ctx) => ctx.text('ok'));

      final response =
          await app.dispatcher.dispatch(_request('POST', '/users'));

      expect(response.status, 405);
      expect(response.headers['allow'], 'GET');
      expect(response.jsonObject['title'], 'Method Not Allowed');
    });

    test('renders an HttpException as a problem document', () async {
      final app = Laska();
      app.get('/users', (ctx) {
        throw HttpException(
          409,
          'The user already exists.',
          code: 'user_exists',
          details: <String, Object?>{'field': 'email'},
        );
      });

      final response = await app.dispatcher.dispatch(_request('GET', '/users'));

      expect(response.status, 409);
      expect(response.jsonObject['code'], 'user_exists');
      expect(response.jsonObject['detail'], 'The user already exists.');
      expect(
        (response.jsonObject['errors']! as Map<String, Object?>)['field'],
        'email',
      );
    });

    test('renders a FormatException as a bad request', () async {
      final app = Laska();
      app.post('/users', (ctx) {
        throw const FormatException('The name is required.');
      });

      final response =
          await app.dispatcher.dispatch(_request('POST', '/users'));

      expect(response.status, 400);
      expect(response.jsonObject['detail'], 'The name is required.');
    });

    test('renders an unknown error as an internal server error', () async {
      final app = Laska();
      app.get('/users', (ctx) {
        throw StateError('the database is gone');
      });

      final response = await app.dispatcher.dispatch(_request('GET', '/users'));

      expect(response.status, 500);
      expect(response.jsonObject['title'], 'Internal Server Error');
    });

    test('keeps the headers of an HttpException', () async {
      final app = Laska();
      app.get('/users', (ctx) {
        throw HttpException(401, 'Missing token.', headers: <String, String>{
          'www-authenticate': 'Bearer',
        });
      });

      final response = await app.dispatcher.dispatch(_request('GET', '/users'));

      expect(response.status, 401);
      expect(response.headers['www-authenticate'], 'Bearer');
    });
  });

  group('Dispatcher middleware', () {
    test('runs the global middleware before the handler', () async {
      final calls = <String>[];
      final app = Laska();
      app.use((request, next) async {
        calls.add('global');
        return next();
      });
      app.get('/users', (ctx) {
        calls.add('handler');
        return ctx.text('ok');
      });

      final response = await app.dispatcher.dispatch(_request('GET', '/users'));

      expect(response.status, 200);
      expect(calls, <String>['global', 'handler']);
    });

    test('runs the route middleware after the global one', () async {
      final calls = <String>[];
      final app = Laska();
      app.use((request, next) async {
        calls.add('global');
        return next();
      });
      app.get(
        '/users',
        (ctx) {
          calls.add('handler');
          return ctx.text('ok');
        },
        middleware: [
          (request, next) async {
            calls.add('route');
            return next();
          },
        ],
      );

      await app.dispatcher.dispatch(_request('GET', '/users'));

      expect(calls, <String>['global', 'route', 'handler']);
    });

    test('lets a middleware short circuit the chain', () async {
      final app = Laska();
      app.use((request, next) async {
        return ctxUnauthorized();
      });
      app.get('/users', (ctx) => ctx.text('ok'));

      final response = await app.dispatcher.dispatch(_request('GET', '/users'));

      expect(response.status, 401);
    });

    test('runs the middleware of a named alias', () async {
      final calls = <String>[];
      final app = Laska();
      app.alias('auth', (request, next) async {
        calls.add('auth');
        return next();
      });
      app.get(
        '/users',
        (ctx) => ctx.text('ok'),
        middleware: ['auth'],
      );

      await app.dispatcher.dispatch(_request('GET', '/users'));

      expect(calls, <String>['auth']);
    });

    test('throws when an alias is unknown', () {
      final app = Laska();

      expect(
        () => app.get('/users', (ctx) => ctx.text('ok'), middleware: ['nope']),
        throwsArgumentError,
      );
    });

    test('runs a global middleware registered after the route', () async {
      final calls = <String>[];
      final app = Laska();
      app.get('/users', (ctx) {
        calls.add('handler');
        return ctx.text('ok');
      });

      app.use((request, next) async {
        calls.add('global');
        return next();
      });

      await app.dispatcher.dispatch(_request('GET', '/users'));

      expect(calls, <String>['global', 'handler']);
    });

    test('runs the global middleware for the routes of a group', () async {
      final calls = <String>[];
      final app = Laska();
      app.use((request, next) async {
        calls.add('global');
        return next();
      });
      app.group('/admin', (group) {
        group.get('/users', (ctx) {
          calls.add('handler');
          return ctx.text('ok');
        });
      });

      await app.dispatcher.dispatch(_request('GET', '/admin/users'));

      expect(calls, <String>['global', 'handler']);
    });

    test('keeps the middleware of a group inside the group', () async {
      final calls = <String>[];
      final app = Laska();
      app.group('/admin', (group) {
        group.get('/users', (ctx) {
          calls.add('handler');
          return ctx.text('ok');
        });
      }, middleware: [
        (request, next) async {
          calls.add('group');
          return next();
        },
      ]);
      app.get('/public', (ctx) {
        calls.add('public');
        return ctx.text('ok');
      });

      await app.dispatcher.dispatch(_request('GET', '/admin/users'));
      await app.dispatcher.dispatch(_request('GET', '/public'));

      expect(calls, <String>['group', 'handler', 'public']);
    });

    test('finds an alias of the application inside a group', () async {
      final calls = <String>[];
      final app = Laska();
      app.alias('auth', (request, next) async {
        calls.add('auth');
        return next();
      });
      app.group('/admin', (group) {
        group.get('/users', (ctx) => ctx.text('ok'), middleware: ['auth']);
      });

      await app.dispatcher.dispatch(_request('GET', '/admin/users'));

      expect(calls, <String>['auth']);
    });

    test('runs the middleware of nested groups from the outside in', () async {
      final calls = <String>[];
      final app = Laska();
      app.group('/v1', (outer) {
        outer.group('/admin', (inner) {
          inner.get('/users', (ctx) {
            calls.add('handler');
            return ctx.text('ok');
          });
        }, middleware: [
          (request, next) async {
            calls.add('inner');
            return next();
          },
        ]);
      }, middleware: [
        (request, next) async {
          calls.add('outer');
          return next();
        },
      ]);

      await app.dispatcher.dispatch(_request('GET', '/v1/admin/users'));

      expect(calls, <String>['outer', 'inner', 'handler']);
    });
  });
}

Response ctxUnauthorized() => Response.json(
      <String, Object?>{'error': 'unauthorized'},
      status: 401,
    );
