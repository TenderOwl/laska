import 'dart:io';

import 'package:laska_cli/src/cli.dart';
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

const String _contractV1 = '''
syntax = "proto3";

package users.v1;

service UsersService {
  rpc GetUser(GetUserRequest) returns (User) {
    option (google.api.http) = { get: "/v1/users/{id}" };
  }
}

message User {
  string id = 1;
}

message GetUserRequest {
  string id = 1;
}
''';

const String _contractV2 = '''
syntax = "proto3";

package users.v2;

service UsersService {
  rpc GetUser(GetUserRequest) returns (User) {
    option (google.api.http) = { get: "/v2/users/{id}" };
  }
}

message User {
  string id = 1;
}

message GetUserRequest {
  string id = 1;
}
''';

void main() {
  late Directory workspace;

  setUp(() {
    workspace = Directory.systemTemp.createTempSync('laska_matrix_test');
  });

  tearDown(() {
    workspace.deleteSync(recursive: true);
  });

  void writeContract(String name, String source) {
    final directory = Directory('${workspace.path}/$name')
      ..createSync(recursive: true);
    File('${directory.path}/users.proto').writeAsStringSync(source);
  }

  group('laska contract matrix', () {
    test('writes the matrix of the versions given one by one', () async {
      writeContract('v1', _contractV1);
      writeContract('v2', _contractV2);

      final result = await _run(<String>[
        'contract',
        'matrix',
        '--version',
        '${workspace.path}/v1',
        '--version',
        '${workspace.path}/v2',
      ]);

      expect(result.code, 0, reason: result.err);
      expect(result.out, contains('client \\ server'));
      expect(result.out, contains('v1'));
      expect(result.out, contains('v2'));
      expect(result.out, contains('yes'));
    });

    test('reads the versions from the directories of a directory', () async {
      writeContract('v1', _contractV1);
      writeContract('v2', _contractV2);

      final result = await _run(<String>[
        'contract',
        'matrix',
        '--dir',
        workspace.path,
      ]);

      expect(result.code, 0, reason: result.err);
      expect(result.out, contains('v1'));
      expect(result.out, contains('v2'));
    });

    test('writes the matrix as Markdown in a file', () async {
      writeContract('v1', _contractV1);
      writeContract('v2', _contractV2);

      final output = '${workspace.path}/docs/matrix.md';
      final result = await _run(<String>[
        'contract',
        'matrix',
        '--dir',
        workspace.path,
        '--out',
        output,
      ]);

      expect(result.code, 0, reason: result.err);

      final markdown = File(output).readAsStringSync();
      expect(markdown, contains('| client \\ server | v1 | v2 |'));
      expect(markdown, contains('| v1 | yes | yes* |'));
    });

    test('reports the difference of every pair', () async {
      writeContract('v1', _contractV1);
      writeContract('v2', _contractV2);

      final result = await _run(<String>[
        'contract',
        'matrix',
        '--dir',
        workspace.path,
        '--details',
      ]);

      expect(result.code, 0, reason: result.err);
      expect(result.out, contains('v1 -> v2:'));
      expect(result.out, contains('the REST binding changed'));
    });

    test('refuses a matrix of a single version', () async {
      writeContract('v1', _contractV1);

      final result = await _run(<String>[
        'contract',
        'matrix',
        '--version',
        '${workspace.path}/v1',
      ]);

      expect(result.code, 64);
      expect(result.err, contains('at least two versions'));
    });

    test('refuses a directory that does not exist', () async {
      final result = await _run(<String>[
        'contract',
        'matrix',
        '--dir',
        '${workspace.path}/missing',
      ]);

      expect(result.code, 66);
      expect(result.err, contains('does not exist'));
    });

    test('refuses a version without a contract', () async {
      writeContract('v1', _contractV1);
      Directory('${workspace.path}/v2').createSync(recursive: true);

      final result = await _run(<String>[
        'contract',
        'matrix',
        '--dir',
        workspace.path,
      ]);

      expect(result.code, 66);
      expect(result.err, contains('No .proto files found'));
    });
  });
}
