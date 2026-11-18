import 'dart:io';

import 'package:laska_cli/src/cli.dart';
import 'package:laska_cli/src/deploy.dart';
import 'package:laska_cli/src/workspace.dart';
import 'package:test/test.dart';

/// The result of one run of the command line interface.
typedef CliResult = ({int code, String out, String err});

/// Runs the command line interface in process.
Future<CliResult> _run(List<String> arguments) async {
  final out = StringBuffer();
  final err = StringBuffer();
  final code = await runCli(arguments, out: out, err: err);
  return (code: code, out: out.toString(), err: err.toString());
}

void main() {
  late Directory workspace;

  setUp(() {
    workspace = Directory.systemTemp.createTempSync('laska_deploy_test');
    File('${workspace.path}/laska.yaml').writeAsStringSync('''
services:
  - name: users
    entrypoint: services/users/bin/server.dart
    port: 8080
  - name: orders
    entrypoint: services/orders/bin/server.dart
    port: 8081
''');
  });

  tearDown(() {
    if (workspace.existsSync()) {
      workspace.deleteSync(recursive: true);
    }
  });

  group('laska deploy:dockerfile', () {
    test('writes a Dockerfile for every service', () async {
      final result = await _run(<String>[
        'deploy:dockerfile',
        '--manifest',
        '${workspace.path}/laska.yaml',
        '--out',
        '${workspace.path}/deploy',
      ]);

      expect(result.code, 0);

      final dockerfile = File('${workspace.path}/deploy/users/Dockerfile');
      expect(dockerfile.existsSync(), isTrue);

      final content = dockerfile.readAsStringSync();
      expect(content, contains('FROM dart:3.14 AS build'));
      expect(content, contains('dart compile exe bin/server.dart'));
      expect(content, contains('EXPOSE 8080'));
      expect(
        File('${workspace.path}/deploy/orders/Dockerfile').existsSync(),
        isTrue,
      );
    });

    test('fails when the manifest does not exist', () async {
      final result = await _run(<String>[
        'deploy:dockerfile',
        '--manifest',
        '${workspace.path}/missing.yaml',
      ]);

      expect(result.code, 66);
      expect(result.err, contains('does not exist'));
    });
  });

  group('laska deploy:k8s', () {
    test('writes the manifests of every service', () async {
      final result = await _run(<String>[
        'deploy:k8s',
        '--manifest',
        '${workspace.path}/laska.yaml',
        '--out',
        '${workspace.path}/deploy',
        '--namespace',
        'laska',
      ]);

      expect(result.code, 0);

      final manifest = File('${workspace.path}/deploy/users.yaml');
      expect(manifest.existsSync(), isTrue);

      final content = manifest.readAsStringSync();
      expect(content, contains('kind: Deployment'));
      expect(content, contains('kind: Service'));
      expect(content, contains('name: users'));
      expect(content, contains('namespace: laska'));
      expect(content, contains('containerPort: 8080'));
      expect(content, contains('image: laska/users:latest'));
    });
  });

  group('renderKubernetes', () {
    test('holds a deployment and a service', () {
      final content = renderKubernetes(
        const WorkspaceService(
          name: 'users',
          entrypoint: 'bin/server.dart',
          port: 8080,
        ),
      );

      expect(content, contains('apiVersion: apps/v1'));
      expect(content, contains('apiVersion: v1'));
      expect(content.split('---'), hasLength(2));
    });
  });

  group('renderDockerfile', () {
    test('compiles the service and runs it alone', () {
      final content = renderDockerfile(
        const WorkspaceService(
          name: 'users',
          entrypoint: 'bin/server.dart',
          port: 8080,
        ),
      );

      expect(content, contains('FROM scratch'));
      expect(content, contains('ENTRYPOINT ["/app/server"]'));
    });
  });
}
