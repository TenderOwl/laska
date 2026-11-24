import 'dart:convert';
import 'dart:io';

import 'package:laska_core/laska_core.dart';
import 'package:test/test.dart';

void main() {
  group('the lifecycle of the application', () {
    test('runs the hooks in the order of the phases', () async {
      final app = Laska();
      final events = <String>[];
      app.onStart(() => events.add('start'));
      app.onReady(() => events.add('ready'));
      app.onShutdown(() => events.add('shutdown'));

      final server = LaskaServer(app, options: const ServeOptions(port: 0));
      await server.start();
      await server.ready();

      expect(events, <String>['start', 'ready']);

      await server.stop();

      expect(events, <String>['start', 'ready', 'shutdown']);
    });

    test('runs the hooks of the groups after the ones of the application',
        () async {
      final app = Laska();
      final events = <String>[];
      app.onStart(() => events.add('app.start'));
      app.group('/api', (group) {
        group.onStart(() => events.add('group.start'));
        group.group('/v1', (nested) {
          nested.onStart(() => events.add('nested.start'));
        });
      });

      final server = LaskaServer(app, options: const ServeOptions(port: 0));
      await server.start();
      await server.ready();
      await server.stop();

      expect(
        events,
        <String>['app.start', 'group.start', 'nested.start'],
      );
    });

    test('runs the hooks of the ready phase when the port is bound', () async {
      final app = Laska();
      HttpServer? bound;
      late LaskaServer server;
      app.onReady(() => bound = server.server);

      server = LaskaServer(app, options: const ServeOptions(port: 0));
      await server.start();
      await server.ready();

      expect(bound, isNotNull);
      await server.stop();
    });

    test('keeps the service from starting when a hook fails', () async {
      final app = Laska();
      app.onStart(() => throw StateError('the hook failed'));

      final server = LaskaServer(app, options: const ServeOptions(port: 0));

      await expectLater(server.start(), throwsStateError);
      expect(server.server, isNull);
    });

    test('closes the other resources when a shutdown hook fails', () async {
      final app = Laska();
      final lines = <String>[];
      app.logger = Logger(sink: lines.add);
      final events = <String>[];
      app.onShutdown(() => throw StateError('the hook failed'));
      app.onShutdown(() => events.add('second'));

      final server = LaskaServer(app, options: const ServeOptions(port: 0));
      await server.start();
      await server.ready();
      await server.stop();

      expect(events, <String>['second']);
      expect(lines, hasLength(1));
      final record = jsonDecode(lines.single) as Map<String, Object?>;
      expect(record['level'], 'error');
      expect('${record['message']}', contains('shutdown'));
    });

    test('runs the shutdown hooks after the last answer was written', () async {
      final app = Laska();
      final events = <String>[];
      app.get('/slow', (ctx) async {
        await Future<void>.delayed(const Duration(milliseconds: 50));
        events.add('answer');
        return ctx.text('done');
      });
      app.onShutdown(() => events.add('shutdown'));

      final server = LaskaServer(app, options: const ServeOptions(port: 0));
      await server.start();
      await server.ready();

      final client = HttpClient();
      final response = await client.getUrl(
        Uri.parse('http://127.0.0.1:${server.server!.port}/slow'),
      );
      await response.close();

      await server.stop();

      expect(events, <String>['answer', 'shutdown']);
    });
  });

  group('the serve helper', () {
    test('runs the hooks of the start and of the ready phase', () async {
      final app = Laska();
      final events = <String>[];
      app.onStart(() => events.add('start'));
      app.onReady(() => events.add('ready'));

      final server = await serve(app, port: 0);

      expect(events, <String>['start', 'ready']);
      await server.close(force: true);
    });
  });
}
