import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:laska_core/laska_core.dart';
import 'package:test/test.dart';

Future<HttpClientResponse> _get(HttpServer server, String path) async {
  final client = HttpClient();
  final request = await client.getUrl(
    Uri.parse('http://127.0.0.1:${server.port}$path'),
  );
  final response = await request.close();
  client.close();
  return response;
}

void main() {
  group('LaskaServer', () {
    test('serves the routes of the application', () async {
      final app = Laska();
      app.get('/users', (ctx) => ctx.json(<String, Object?>{'ok': true}));

      final server = await serve(app, port: 0);
      final response = await _get(server, '/users');
      final body = await response.transform(utf8.decoder).join();
      await server.close(force: true);

      expect(response.statusCode, 200);
      expect(jsonDecode(body), <String, Object?>{'ok': true});
    });

    test('answers an unknown path with a problem document', () async {
      final app = Laska();

      final server = await serve(app, port: 0);
      final response = await _get(server, '/nope');
      final body = await response.transform(utf8.decoder).join();
      await server.close(force: true);

      expect(response.statusCode, 404);
      expect(
          response.headers.contentType?.mimeType, 'application/problem+json');
      expect((jsonDecode(body) as Map<String, Object?>)['status'], 404);
    });

    test('binds a port', () async {
      final app = Laska();
      final server = LaskaServer(
        app,
        options: const ServeOptions(port: 0),
      );
      final httpServer = await server.start();

      expect(httpServer.port, greaterThan(0));

      await server.stop();
    });

    test('lets a running request finish while it stops', () async {
      final completer = Completer<void>();
      final app = Laska();
      app.get('/slow', (ctx) async {
        await completer.future;
        return ctx.text('done');
      });

      final server = LaskaServer(
        app,
        options: const ServeOptions(port: 0),
      );
      final httpServer = await server.start();

      final responseFuture = _get(httpServer, '/slow');
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(server.inFlight, 1);

      final stopFuture = server.stop();
      completer.complete();
      final response = await responseFuture;
      await stopFuture;

      expect(response.statusCode, 200);
      expect(await response.transform(utf8.decoder).join(), 'done');
    });

    test('stops the server twice without an error', () async {
      final app = Laska();
      final server = LaskaServer(
        app,
        options: const ServeOptions(port: 0),
      );
      await server.start();

      await server.stop();
      await server.stop();
    });
  });
}
