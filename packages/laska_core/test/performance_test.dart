import 'package:laska_core/laska_core.dart';
import 'package:test/test.dart';

/// The budget of the hot path.
///
/// The budget is not a number of nanoseconds — that would depend on the
/// machine — but a number of objects the runtime is allowed to create for a
/// request. The assertions below hold the runtime to it.
void main() {
  group('the budget of the routing', () {
    test('a static route does not allocate a map of parameters', () {
      final router = Router()..add('GET', '/v1/users', _ok);

      final match = router.lookup('GET', '/v1/users');

      expect(match, isNotNull);
      expect(
        identical(match!.params, const <String, String>{}),
        isTrue,
        reason: 'the empty map of the parameters is shared, not built again',
      );
    });

    test('a route with a parameter allocates one map of parameters', () {
      final router = Router()..add('GET', '/v1/users/:id', _ok);

      final match = router.lookup('GET', '/v1/users/42');

      expect(match, isNotNull);
      expect(match!.params, <String, String>{'id': '42'});
    });

    test('a route that does not match allocates no map of parameters', () {
      final router = Router()..add('GET', '/v1/users/:id', _ok);

      final match = router.lookup('GET', '/v1/orders/42');

      expect(match, isNull);
    });

    test('the tables of the router are built when the route is registered', () {
      final router = Router()
        ..add('GET', '/v1/users', _ok)
        ..add('GET', '/v1/:id', _ok)
        ..add('POST', '/v1/users', _ok);

      expect(router.routes, hasLength(3));

      // The score of a route never changes, so it is computed once. A static
      // segment beats a parameter.
      final static = router.routes.first;
      final parameter = router.routes[1];
      expect(static.score, greaterThan(parameter.score));
    });
  });

  group('the budget of the dispatch', () {
    test('the chain of the middleware is built once and kept', () async {
      final app = Laska();
      app.get('/v1/users', (ctx) => ctx.text('ok'));

      await app.dispatcher.dispatch(_request('/v1/users'));
      await app.dispatcher.dispatch(_request('/v1/users'));
      await app.dispatcher.dispatch(_request('/v1/users'));

      expect(app.dispatcher.chainBuilds, 1);
    });

    test('the chain is built again when the middleware changes', () async {
      final app = Laska();
      app.get('/v1/users', (ctx) => ctx.text('ok'));

      await app.dispatcher.dispatch(_request('/v1/users'));
      expect(app.dispatcher.chainBuilds, 1);

      app.use((request, next) => next());
      await app.dispatcher.dispatch(_request('/v1/users'));
      expect(app.dispatcher.chainBuilds, 2);
    });

    test('the request is not copied for the parameters of the route', () async {
      final app = Laska();
      String? id;
      app.get('/v1/users/:id', (ctx) {
        id = ctx.params['id'];
        return ctx.text('ok');
      });

      final request = _request('/v1/users/42');
      await app.dispatcher.dispatch(request);

      expect(id, '42');
      expect(request.params, <String, String>{'id': '42'});
      expect(request.routePattern, '/v1/users/:id');
    });
  });
}

/// Builds a request like the server builds one.
Request _request(String path) => Request(
      method: 'GET',
      path: path,
      uri: 'http://127.0.0.1:8080$path',
      query: const <String, String>{},
      headers: const <String, String>{},
    );

/// A handler that answers with a short text.
Response _ok(Context ctx) => ctx.text('ok');
