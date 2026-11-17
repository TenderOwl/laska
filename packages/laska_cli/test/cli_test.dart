import 'dart:io';

import 'package:laska_cli/src/cli.dart';
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

/// The tests of the CLI start real processes, so they need more time than the
/// default timeout of thirty seconds.
const Timeout _timeout = Timeout(Duration(minutes: 3));

/// The result of one run of the command line interface.
typedef CliResult = ({int code, String out, String err});

/// Runs the command line interface in process.
///
/// The commands are driven in process, so the tests do not pay for a new
/// virtual machine per command.
Future<CliResult> _run(
  List<String> arguments, {
  Map<String, String>? environment,
}) async {
  final out = StringBuffer();
  final err = StringBuffer();
  final code = await runCli(
    arguments,
    out: out,
    err: err,
    environment: environment,
  );
  return (code: code, out: out.toString(), err: err.toString());
}

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

      expect(result.code, 0, reason: result.err);
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

      expect(result.code, 65);
      expect(result.err, contains('unknown type'));
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

      expect(result.code, 1);
      expect(result.out, contains('BREAKING'));
      expect(result.out, contains('users.v1.User.email'));
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

      expect(result.code, 0);
      expect(result.out, contains('No changes detected'));
    });
  });

  group('laska route:list', () {
    test('prints the route table of the service', () async {
      final result = await _run(<String>[
        'route:list',
        '--entrypoint',
        'test/fixtures/service.dart',
      ]);

      expect(result.code, 0, reason: result.err);
      final output = result.out;
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

      expect(result.code, 66);
      expect(result.err, contains('does not exist'));
    });
  }, timeout: _timeout);

  group('laska dev', () {
    test('fails when there is neither a manifest nor an entrypoint', () async {
      final result = await _run(<String>[
        'dev',
        '--manifest',
        '${workspace.path}/missing.yaml',
        '--no-collector',
      ]);

      expect(result.code, 66);
      expect(result.err, contains('No entrypoint found'));
    });

    test('fails when the entrypoint of a service does not exist', () async {
      File('${workspace.path}/laska.yaml').writeAsStringSync('''
services:
  - name: users
    entrypoint: services/users/bin/server.dart
    port: 8080
''');

      final result = await _run(<String>[
        'dev',
        '--manifest',
        '${workspace.path}/laska.yaml',
        '--no-collector',
      ]);

      expect(result.code, 66);
      expect(result.err, contains('does not exist'));
    });
  }, timeout: _timeout);

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

      expect(result.code, 0, reason: result.err);
      expect(result.out, contains('applied 1 migration(s)'));
      expect(result.out, contains('001_create_users'));
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

      expect(first.code, 0, reason: first.err);
      expect(second.code, 0, reason: second.err);
      expect(second.out, contains('applied 0 migration(s)'));
    });
  }, timeout: _timeout);
}
