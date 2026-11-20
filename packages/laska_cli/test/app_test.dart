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
    workspace = Directory.systemTemp.createTempSync('laska_app_test');
  });

  tearDown(() {
    if (workspace.existsSync()) {
      workspace.deleteSync(recursive: true);
    }
  });

  Future<void> _scaffoldService([String name = 'users']) async {
    final result = await _run(<String>[
      'new',
      'service',
      name,
      '--out',
      workspace.path,
      '--manifest',
      '${workspace.path}/laska.yaml',
    ]);

    expect(result.code, 0);
  }

  group('laska new app', () {
    test('writes an app that is ready to run', () async {
      await _scaffoldService();

      final result = await _run(<String>[
        'new',
        'app',
        'admin',
        '--out',
        workspace.path,
        '--manifest',
        '${workspace.path}/laska.yaml',
      ]);

      expect(result.code, 0);

      final app = Directory('${workspace.path}/admin');
      expect(File('${app.path}/bin/server.dart').existsSync(), isTrue);
      expect(File('${app.path}/lib/app.dart').existsSync(), isTrue);
      expect(File('${app.path}/web/index.html').existsSync(), isTrue);
      expect(File('${app.path}/web/app.js').existsSync(), isTrue);
      expect(File('${app.path}/web/app.css').existsSync(), isTrue);
      expect(File('${app.path}/test/app_test.dart').existsSync(), isTrue);
      expect(File('${app.path}/pubspec.yaml').existsSync(), isTrue);
    });

    test('the app waits for its routes before it serves', () async {
      await _scaffoldService();

      await _run(<String>[
        'new',
        'app',
        'admin',
        '--out',
        workspace.path,
        '--manifest',
        '${workspace.path}/laska.yaml',
      ]);

      final entrypoint =
          File('${workspace.path}/admin/bin/server.dart').readAsStringSync();

      expect(entrypoint, contains('await registerApp(app);'));
    });

    test('the app serves the frontend of the workspace', () async {
      await _scaffoldService();

      await _run(<String>[
        'new',
        'app',
        'admin',
        '--out',
        workspace.path,
        '--manifest',
        '${workspace.path}/laska.yaml',
      ]);

      final code =
          File('${workspace.path}/admin/lib/app.dart').readAsStringSync();

      expect(code, contains('app.staticFiles('));
      expect(code, contains("fallback: 'index.html',"));
    });

    test('the app looks for the frontend in its own package', () async {
      await _scaffoldService();

      await _run(<String>[
        'new',
        'app',
        'admin',
        '--out',
        workspace.path,
        '--manifest',
        '${workspace.path}/laska.yaml',
      ]);

      final code =
          File('${workspace.path}/admin/lib/app.dart').readAsStringSync();

      // The files of the frontend live in the package of the app, so the app
      // serves them no matter the directory it was started in.
      expect(code, contains('await frontendDirectory('));
      expect(
        code,
        contains("packageUri: Uri.parse('package:admin_app/app.dart'),"),
      );
      expect(
        code,
        contains("configured: Platform.environment['LASKA_WEB_ROOT'],"),
      );
      expect(code, isNot(contains("?? 'web'")));
    });

    test('the app calls the service behind it with the typed client', () async {
      await _scaffoldService();

      await _run(<String>[
        'new',
        'app',
        'admin',
        '--out',
        workspace.path,
        '--manifest',
        '${workspace.path}/laska.yaml',
      ]);

      final code =
          File('${workspace.path}/admin/lib/app.dart').readAsStringSync();

      expect(
          code,
          contains(
              'import \'package:users_service/generated/users.pb.dart\';'));
      expect(code, contains('final UsersServiceClient _client;'));
      expect(code,
          contains('registerUsersService(app, UsersProxy(usersClient), '));
      expect(
        code,
        contains(
          '_client.getUser(request, headers: _headersOfTheCaller());',
        ),
      );
    });

    test('the app passes the headers of the caller to the service behind it',
        () async {
      await _scaffoldService();

      await _run(<String>[
        'new',
        'app',
        'admin',
        '--out',
        workspace.path,
        '--manifest',
        '${workspace.path}/laska.yaml',
      ]);

      final code =
          File('${workspace.path}/admin/lib/app.dart').readAsStringSync();

      expect(code, contains('request.header(\'authorization\')'));
      expect(code, contains('runZoned('));
    });

    test('the app depends on the package of the service behind it', () async {
      await _scaffoldService();

      await _run(<String>[
        'new',
        'app',
        'admin',
        '--out',
        workspace.path,
        '--manifest',
        '${workspace.path}/laska.yaml',
      ]);

      final pubspec =
          File('${workspace.path}/admin/pubspec.yaml').readAsStringSync();

      expect(pubspec, contains('users_service: {path: '));
    });

    test('the app is added to the manifest with the kind of an app', () async {
      await _scaffoldService();

      await _run(<String>[
        'new',
        'app',
        'admin',
        '--out',
        workspace.path,
        '--manifest',
        '${workspace.path}/laska.yaml',
      ]);

      final model = readWorkspace(File('${workspace.path}/laska.yaml'));

      expect(model.services, hasLength(2));
      final app = model.services.last;
      expect(app.name, 'admin');
      expect(app.kind, WorkspaceServiceKind.app);
      expect(app.entrypoint, 'admin/bin/server.dart');
      expect(app.dependsOn, <String>['users']);
    });

    test('the app takes the first port no service listens to', () async {
      await _scaffoldService();

      await _run(<String>[
        'new',
        'app',
        'admin',
        '--out',
        workspace.path,
        '--manifest',
        '${workspace.path}/laska.yaml',
      ]);

      final model = readWorkspace(File('${workspace.path}/laska.yaml'));

      expect(model.services.last.port, 8081);
    });

    test('the port of the app may be given', () async {
      await _scaffoldService();

      await _run(<String>[
        'new',
        'app',
        'admin',
        '--port',
        '8090',
        '--out',
        workspace.path,
        '--manifest',
        '${workspace.path}/laska.yaml',
      ]);

      final model = readWorkspace(File('${workspace.path}/laska.yaml'));

      expect(model.services.last.port, 8090);
    });

    test('the app calls only the services it is given', () async {
      await _scaffoldService('users');
      await _scaffoldService('orders');

      await _run(<String>[
        'new',
        'app',
        'admin',
        '--calls',
        'orders',
        '--out',
        workspace.path,
        '--manifest',
        '${workspace.path}/laska.yaml',
      ]);

      final code =
          File('${workspace.path}/admin/lib/app.dart').readAsStringSync();

      expect(code, contains('OrdersServiceClient'));
      expect(code, isNot(contains('UsersServiceClient')));
    });

    test('fails when the service of the app is unknown', () async {
      await _scaffoldService();

      final result = await _run(<String>[
        'new',
        'app',
        'admin',
        '--calls',
        'billing',
        '--out',
        workspace.path,
        '--manifest',
        '${workspace.path}/laska.yaml',
      ]);

      expect(result.code, 65);
      expect(result.err, contains('holds no service called "billing"'));
    });

    test('fails without the name of the app', () async {
      final result = await _run(<String>['new', 'app']);

      expect(result.code, 64);
      expect(result.err, contains('Missing the name'));
    });

    test('the image of an app holds the files of the frontend', () {
      final content = renderDockerfile(
        const WorkspaceService(
          name: 'admin',
          entrypoint: 'admin/bin/server.dart',
          port: 8081,
          kind: WorkspaceServiceKind.app,
        ),
      );

      expect(content, contains('COPY --from=build /app/web /app/web'));
      expect(content, contains('ENV LASKA_WEB_ROOT=/app/web'));
    });

    test('the image of a service holds no files of a frontend', () {
      final content = renderDockerfile(
        const WorkspaceService(
          name: 'users',
          entrypoint: 'users/bin/server.dart',
          port: 8080,
        ),
      );

      expect(content, isNot(contains('LASKA_WEB_ROOT')));
    });
  });

  group('the kind of a service', () {
    test('is read from the manifest', () {
      final model = readWorkspace(
          File('${workspace.path}/laska.yaml')..writeAsStringSync('''
services:
  - name: users
    entrypoint: users/bin/server.dart
    port: 8080
  - name: admin
    kind: app
    entrypoint: admin/bin/server.dart
    port: 8081
'''));

      expect(model.services.first.kind, WorkspaceServiceKind.service);
      expect(model.services.last.kind, WorkspaceServiceKind.app);
    });

    test('a service without a kind is a service of a contract', () {
      final model = readWorkspace(
          File('${workspace.path}/laska.yaml')..writeAsStringSync('''
services:
  - name: users
    entrypoint: users/bin/server.dart
    port: 8080
'''));

      expect(model.services.single.kind, WorkspaceServiceKind.service);
    });

    test('a kind nobody knows is refused', () {
      final file = File('${workspace.path}/laska.yaml')..writeAsStringSync('''
services:
  - name: users
    kind: gateway
    entrypoint: users/bin/server.dart
    port: 8080
''');

      expect(
        () => readWorkspace(file),
        throwsA(
          isA<WorkspaceException>().having(
            (error) => error.message,
            'message',
            contains('is not a kind the runtime knows'),
          ),
        ),
      );
    });

    test('the kind is written when it is not the default', () {
      final yaml = renderWorkspace(
        const Workspace(
          services: <WorkspaceService>[
            WorkspaceService(
              name: 'users',
              entrypoint: 'users/bin/server.dart',
              port: 8080,
            ),
            WorkspaceService(
              name: 'admin',
              entrypoint: 'admin/bin/server.dart',
              port: 8081,
              kind: WorkspaceServiceKind.app,
            ),
          ],
        ),
      );

      expect(yaml, contains('    kind: app\n'));
      expect(yaml.split('kind:'), hasLength(2));
    });
  });
}
