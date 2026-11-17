import 'dart:io';

import 'package:test/test.dart';

const String _contract = '''
syntax = "proto3";

package users.v1;

message User {
  string id = 1;
  string email = 2;
}
''';

const String _breakingContract = '''
syntax = "proto3";

package users.v1;

message User {
  string id = 1;
}
''';

Future<ProcessResult> _run(
  List<String> arguments, {
  Map<String, String>? environment,
}) =>
    Process.run(
      Platform.resolvedExecutable,
      <String>['run', 'bin/laska.dart', ...arguments],
      workingDirectory: Directory.current.path,
      environment: environment,
    );

void main() {
  late Directory workspace;

  setUp(() {
    workspace = Directory.systemTemp.createTempSync('laska_cli_test');
  });

  tearDown(() {
    workspace.deleteSync(recursive: true);
  });

  void writeContract(String name, String source) {
    final directory = Directory('${workspace.path}/$name')
      ..createSync(recursive: true);
    File('${directory.path}/users.proto').writeAsStringSync(source);
  }

  group('laska contract compile', () {
    test('writes generated code and an OpenAPI document', () async {
      writeContract('proto', _contract);

      final result = await _run(<String>[
        'contract',
        'compile',
        '--proto',
        '${workspace.path}/proto',
        '--out',
        '${workspace.path}/out',
      ]);

      expect(result.exitCode, 0, reason: result.stderr.toString());
      expect(
        File('${workspace.path}/out/users.pb.dart').existsSync(),
        isTrue,
      );
      expect(File('${workspace.path}/out/openapi.json').existsSync(), isTrue);
    });

    test('fails on an inconsistent contract', () async {
      writeContract(
        'proto',
        '''
syntax = "proto3";

message User {
  Unknown id = 1;
}
''',
      );

      final result = await _run(<String>[
        'contract',
        'compile',
        '--proto',
        '${workspace.path}/proto',
        '--out',
        '${workspace.path}/out',
      ]);

      expect(result.exitCode, 65);
      expect(result.stderr.toString(), contains('unknown type'));
    });
  });

  group('laska contract diff', () {
    test('reports a breaking change and fails', () async {
      writeContract('base', _contract);
      writeContract('candidate', _breakingContract);

      final result = await _run(<String>[
        'contract',
        'diff',
        '--base',
        '${workspace.path}/base',
        '--candidate',
        '${workspace.path}/candidate',
      ]);

      expect(result.exitCode, 1);
      expect(result.stdout.toString(), contains('BREAKING'));
      expect(result.stdout.toString(), contains('users.v1.User.email'));
    });

    test('passes for a compatible contract', () async {
      writeContract('base', _contract);
      writeContract('candidate', _contract);

      final result = await _run(<String>[
        'contract',
        'diff',
        '--base',
        '${workspace.path}/base',
        '--candidate',
        '${workspace.path}/candidate',
      ]);

      expect(result.exitCode, 0);
      expect(result.stdout.toString(), contains('No changes detected'));
    });
  });

  group('laska route:list', () {
    test('prints the route table of the service', () async {
      final result = await _run(<String>[
        'route:list',
        '--entrypoint',
        'test/fixtures/service.dart',
      ]);

      expect(result.exitCode, 0, reason: result.stderr.toString());
      final output = result.stdout.toString();
      expect(output, contains('METHOD'));
      expect(output, contains('/users'));
      expect(output, contains('createUser'));
    });

    test('fails when the entrypoint does not exist', () async {
      final result = await _run(<String>[
        'route:list',
        '--entrypoint',
        '${workspace.path}/missing.dart',
      ]);

      expect(result.exitCode, 66);
      expect(result.stderr.toString(), contains('does not exist'));
    });
  });

  group('laska migrate:run', () {
    test('applies the migrations of the service', () async {
      final migrations = Directory('${workspace.path}/migrations')
        ..createSync(recursive: true);
      File('${migrations.path}/001_create_users.sql')
          .writeAsStringSync('CREATE TABLE users (id INTEGER PRIMARY KEY);');

      final result = await _run(
        <String>[
          'migrate:run',
          '--entrypoint',
          'test/fixtures/service_with_db.dart',
          '--directory',
          migrations.path,
        ],
        environment: <String, String>{
          'LASKA_TEST_DATABASE': '${workspace.path}/service.sqlite',
        },
      );

      expect(result.exitCode, 0, reason: result.stderr.toString());
      expect(result.stdout.toString(), contains('applied 1 migration(s)'));
      expect(result.stdout.toString(), contains('001_create_users'));
    });

    test('does not apply a migration twice', () async {
      final migrations = Directory('${workspace.path}/migrations')
        ..createSync(recursive: true);
      File('${migrations.path}/001_create_users.sql')
          .writeAsStringSync('CREATE TABLE users (id INTEGER PRIMARY KEY);');

      final arguments = <String>[
        'migrate:run',
        '--entrypoint',
        'test/fixtures/service_with_db.dart',
        '--directory',
        migrations.path,
      ];
      final environment = <String, String>{
        'LASKA_TEST_DATABASE': '${workspace.path}/service.sqlite',
      };

      final first = await _run(arguments, environment: environment);
      final second = await _run(arguments, environment: environment);

      expect(first.exitCode, 0, reason: first.stderr.toString());
      expect(second.exitCode, 0, reason: second.stderr.toString());
      expect(second.stdout.toString(), contains('applied 0 migration(s)'));
    });
  });
}
