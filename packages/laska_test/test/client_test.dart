import 'package:laska_core/laska_core.dart';
import 'package:laska_test/laska_test.dart';
import 'package:test/test.dart';

void main() {
  late Laska app;
  late TestClient client;

  setUp(() {
    app = Laska();
    app.get('/users', (ctx) => ctx.json(<String, Object?>{'ok': true}));
    app.get(
        '/users/:id',
        (ctx) => ctx.json(<String, Object?>{
              'id': ctx.params['id'],
            }));
    app.post('/users', (ctx) async {
      final body = ctx.request.json();
      return ctx.json(body, status: 201);
    });
    app.get('/missing', (ctx) {
      throw HttpException(404, 'No such user.');
    });
    client = testClient(app);
  });

  group('TestClient', () {
    test('sends a request to the application', () async {
      final response = await client.get('/users');

      expect(response.status, 200);
      expect(response.json, <String, Object?>{'ok': true});
    });

    test('passes the route parameters', () async {
      final response = await client.get('/users/42');

      expect(response.json, <String, Object?>{'id': '42'});
    });

    test('sends a JSON body', () async {
      final response = await client.post(
        '/users',
        body: <String, Object?>{'name': 'Ada'},
      );

      expect(response.status, 201);
      expect(response.json, <String, Object?>{'name': 'Ada'});
    });

    test('passes the query parameters', () async {
      app.get('/search', (ctx) => ctx.text(ctx.query['q']!));

      final response = await client.get('/search?q=dart');

      expect(response.body, 'dart');
    });

    test('passes the headers', () async {
      app.get('/who', (ctx) => ctx.text(ctx.request.header('x-tenant')!));

      final response = await client.get(
        '/who',
        headers: <String, String>{'x-tenant': 'acme'},
      );

      expect(response.body, 'acme');
    });

    test('renders the error of the application', () async {
      final response = await client.get('/missing');

      expect(response.status, 404);
      expect(response.jsonObject['detail'], 'No such user.');
    });
  });

  group('TestResponse', () {
    test('checks the status', () async {
      final response = await client.get('/users');

      expect(response.expectStatus(200), same(response));
      expect(
        () => response.expectStatus(404),
        throwsA(isA<LaskaTestFailure>()),
      );
    });

    test('checks the JSON body', () async {
      final response = await client.get('/users');

      expect(
          response.expectJson(<String, Object?>{'ok': true}), same(response));
      expect(
        () => response.expectJson(<String, Object?>{'ok': false}),
        throwsA(isA<LaskaTestFailure>()),
      );
    });

    test('checks a header', () async {
      final powered = Laska();
      powered.use((request, next) async {
        final response = await next();
        response.headers['x-powered-by'] = 'laska';
        return response;
      });
      powered.get('/users', (ctx) => ctx.json(<String, Object?>{'ok': true}));

      final response = await testClient(powered).get('/users');

      expect(response.expectHeader('x-powered-by', 'laska'), same(response));
      expect(
        () => response.expectHeader('x-powered-by', 'other'),
        throwsA(isA<LaskaTestFailure>()),
      );
    });

    test('checks a part of the body', () async {
      final response = await client.get('/users');

      expect(response.expectBodyContains('ok'), same(response));
      expect(
        () => response.expectBodyContains('missing'),
        throwsA(isA<LaskaTestFailure>()),
      );
    });

    test('reports a null body as no JSON', () async {
      app.get('/empty', (ctx) => ctx.text(''));

      final response = await client.get('/empty');

      expect(response.json, isNull);
    });
  });
}
