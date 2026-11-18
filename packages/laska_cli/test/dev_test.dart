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

    test('reads the environment of the workspace', () {
      writeManifest('''
environment:
  LOG_LEVEL: debug

services:
  - name: users
    entrypoint: bin/server.dart
    port: 8080
''');

      final result = readWorkspace(File('${workspace.path}/laska.yaml'));

      expect(result.environment, <String, String>{'LOG_LEVEL': 'debug'});
    });

    test('reads the dependencies of a service', () {
      writeManifest('''
services:
  - name: users
    entrypoint: bin/server.dart
    port: 8080
  - name: orders
    entrypoint: bin/orders.dart
    port: 8081
    depends_on: [users]
''');

      final result = readWorkspace(File('${workspace.path}/laska.yaml'));

      expect(result.services.last.dependsOn, <String>['users']);
    });

    test('reads the dependencies of a service written as a list', () {
      writeManifest('''
services:
  - name: users
    entrypoint: bin/server.dart
    port: 8080
  - name: orders
    entrypoint: bin/orders.dart
    port: 8081
    depends_on:
      - users
''');

      final result = readWorkspace(File('${workspace.path}/laska.yaml'));

      expect(result.services.last.dependsOn, <String>['users']);
    });

    test('fails when a service depends on a service that does not exist', () {
      writeManifest('''
services:
  - name: orders
    entrypoint: bin/orders.dart
    port: 8081
    depends_on: [users]
''');

      expect(
        () => readWorkspace(File('${workspace.path}/laska.yaml')),
        throwsA(isA<WorkspaceException>()),
      );
    });

    test('fails when the dependencies form a cycle', () {
      writeManifest('''
services:
  - name: users
    entrypoint: bin/server.dart
    port: 8080
    depends_on: [orders]
  - name: orders
    entrypoint: bin/orders.dart
    port: 8081
    depends_on: [users]
''');

      expect(
        () => readWorkspace(File('${workspace.path}/laska.yaml')),
        throwsA(isA<WorkspaceException>()),
      );
    });

    test('fails when the manifest cannot be read', () {
      writeManifest('services\n');

      expect(
        () => readWorkspace(File('${workspace.path}/laska.yaml')),
        throwsA(isA<WorkspaceException>()),
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

  group('orderServices', () {
    WorkspaceService service(String name, List<String> dependsOn) =>
        WorkspaceService(
          name: name,
          entrypoint: 'bin/$name.dart',
          port: 8080,
          dependsOn: dependsOn,
        );

    test('starts a service after the services it depends on', () {
      final ordered = orderServices(<WorkspaceService>[
        service('orders', <String>['users']),
        service('users', <String>[]),
      ]);

      expect(
        ordered.map((service) => service.name),
        <String>['users', 'orders'],
      );
    });

    test('keeps the order of the services that do not depend on each other',
        () {
      final ordered = orderServices(<WorkspaceService>[
        service('billing', <String>[]),
        service('users', <String>[]),
        service('orders', <String>['users']),
      ]);

      expect(
        ordered.map((service) => service.name),
        <String>['billing', 'users', 'orders'],
      );
    });

    test('fails when the dependencies form a cycle', () {
      expect(
        () => orderServices(<WorkspaceService>[
          service('users', <String>['orders']),
          service('orders', <String>['users']),
        ]),
        throwsA(isA<WorkspaceException>()),
      );
    });
  });

  group('serviceEnvironment', () {
    test('gives every service the address of the other services', () {
      final workspace = Workspace(
        services: <WorkspaceService>[
          WorkspaceService(
            name: 'users',
            entrypoint: 'bin/users.dart',
            port: 8080,
          ),
          WorkspaceService(
            name: 'orders',
            entrypoint: 'bin/orders.dart',
            port: 8081,
          ),
        ],
        environment: <String, String>{'LOG_LEVEL': 'debug'},
      );

      final environment =
          serviceEnvironment(workspace.services.last, workspace);

      expect(environment['USERS_URL'], 'http://127.0.0.1:8080');
      expect(environment['ORDERS_URL'], 'http://127.0.0.1:8081');
      expect(environment['LOG_LEVEL'], 'debug');
    });

    test('lets the service override the environment of the workspace', () {
      final workspace = Workspace(
        services: <WorkspaceService>[
          WorkspaceService(
            name: 'users',
            entrypoint: 'bin/users.dart',
            port: 8080,
            environment: <String, String>{'LOG_LEVEL': 'trace'},
          ),
        ],
        environment: <String, String>{'LOG_LEVEL': 'debug'},
      );

      final environment =
          serviceEnvironment(workspace.services.single, workspace);

      expect(environment['LOG_LEVEL'], 'trace');
    });
  });

  group('waitForPort', () {
    test('returns true when the port answers', () async {
      final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);

      final ready = await waitForPort(
        '127.0.0.1',
        server.port,
        timeout: const Duration(seconds: 5),
      );

      await server.close();

      expect(ready, isTrue);
    });

    test('returns false when the port stays closed', () async {
      final ready = await waitForPort(
        '127.0.0.1',
        1,
        timeout: const Duration(milliseconds: 300),
        interval: const Duration(milliseconds: 50),
      );

      expect(ready, isFalse);
    });
  });
}
