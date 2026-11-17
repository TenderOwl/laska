import 'dart:convert';
import 'dart:io';

import 'package:laska_cli/src/collector.dart';
import 'package:laska_cli/src/workspace.dart';
import 'package:test/test.dart';

void main() {
  late Directory workspace;

  setUp(() {
    workspace = Directory.systemTemp.createTempSync('laska_dev_test');
  });

  tearDown(() {
    if (workspace.existsSync()) {
      workspace.deleteSync(recursive: true);
    }
  });

  void writeManifest(String content) {
    File('${workspace.path}/laska.yaml').writeAsStringSync(content);
  }

  group('readWorkspace', () {
    test('reads the services of the manifest', () {
      writeManifest('''
services:
  - name: users
    entrypoint: services/users/bin/server.dart
    port: 8080
  - name: orders
    entrypoint: services/orders/bin/server.dart
    port: 8081
''');

      final result = readWorkspace(File('${workspace.path}/laska.yaml'));

      expect(result.services, hasLength(2));
      expect(result.services.first.name, 'users');
      expect(
        result.services.first.entrypoint,
        'services/users/bin/server.dart',
      );
      expect(result.services.first.port, 8080);
      expect(result.services.last.name, 'orders');
      expect(result.services.last.port, 8081);
    });

    test('reads the environment of a service', () {
      writeManifest('''
services:
  - name: users
    entrypoint: bin/server.dart
    port: 8080
    environment:
      DATABASE_URL: postgres://localhost/users
      LOG_LEVEL: debug
''');

      final result = readWorkspace(File('${workspace.path}/laska.yaml'));

      expect(
        result.services.first.environment,
        <String, String>{
          'DATABASE_URL': 'postgres://localhost/users',
          'LOG_LEVEL': 'debug',
        },
      );
    });

    test('ignores the comments and the empty lines', () {
      writeManifest('''
# the services of the workspace

services:
  # the users service
  - name: users
    entrypoint: bin/server.dart
    port: 8080
''');

      final result = readWorkspace(File('${workspace.path}/laska.yaml'));

      expect(result.services, hasLength(1));
      expect(result.services.first.name, 'users');
    });

    test('removes the quotes of a value', () {
      writeManifest('''
services:
  - name: "users"
    entrypoint: 'bin/server.dart'
    port: 8080
''');

      final result = readWorkspace(File('${workspace.path}/laska.yaml'));

      expect(result.services.first.name, 'users');
      expect(result.services.first.entrypoint, 'bin/server.dart');
    });

    test('fails when the manifest does not exist', () {
      expect(
        () => readWorkspace(File('${workspace.path}/missing.yaml')),
        throwsA(isA<WorkspaceException>()),
      );
    });

    test('fails when the manifest holds no service', () {
      writeManifest('services:\n');

      expect(
        () => readWorkspace(File('${workspace.path}/laska.yaml')),
        throwsA(isA<WorkspaceException>()),
      );
    });

    test('fails when a service has no entrypoint', () {
      writeManifest('''
services:
  - name: users
    port: 8080
''');

      expect(
        () => readWorkspace(File('${workspace.path}/laska.yaml')),
        throwsA(isA<WorkspaceException>()),
      );
    });
  });

  group('LocalCollector', () {
    late LocalCollector collector;
    late List<String> lines;

    setUp(() async {
      lines = <String>[];
      collector = LocalCollector(sink: lines.add);
      await collector.start(port: 0);
    });

    tearDown(() async {
      await collector.stop();
    });

    Future<void> post(String path, Object payload) async {
      final client = HttpClient();
      final request = await client.postUrl(
        Uri.parse('${collector.endpoint}$path'),
      );
      request.write(jsonEncode(payload));
      final response = await request.close();
      await response.drain<void>();
      client.close();
    }

    test('answers the request of a service', () async {
      await post('/v1/traces', <String, Object?>{
        'resourceSpans': <Object?>[],
      });

      expect(collector.spansReceived, 0);
    });

    test('prints the spans it receives', () async {
      await post('/v1/traces', <String, Object?>{
        'resourceSpans': <Object?>[
          <String, Object?>{
            'scopeSpans': <Object?>[
              <String, Object?>{
                'spans': <Object?>[
                  <String, Object?>{
                    'name': 'http.server',
                    'traceId': '4bf92f3577b34da6a3ce929d0e0e4736',
                    'spanId': '00f067aa0ba902b7',
                    'startTimeUnixNano': '1000000',
                    'endTimeUnixNano': '3500000',
                  },
                ],
              },
            ],
          },
        ],
      });

      expect(collector.spansReceived, 1);
      expect(lines.single, contains('http.server'));
      expect(lines.single, contains('4bf92f35'));
      expect(lines.single, contains('2.5ms'));
    });

    test('counts a metric payload', () async {
      await post('/v1/metrics', <String, Object?>{
        'resourceMetrics': <Object?>[],
      });

      expect(collector.metricsReceived, 1);
    });

    test('ignores a payload it cannot read', () async {
      final client = HttpClient();
      final request = await client.postUrl(
        Uri.parse('${collector.endpoint}/v1/traces'),
      );
      request.write('not json');
      final response = await request.close();
      await response.drain<void>();
      client.close();

      expect(response.statusCode, 200);
      expect(collector.spansReceived, 0);
    });
  });
}
