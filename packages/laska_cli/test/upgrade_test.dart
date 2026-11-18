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
    workspace = Directory.systemTemp.createTempSync('laska_upgrade_test');
  });

  tearDown(() {
    workspace.deleteSync(recursive: true);
  });

  void writeContract(String name, String source) {
    final directory = Directory('${workspace.path}/$name')
      ..createSync(recursive: true);
    File('${directory.path}/users.proto').writeAsStringSync(source);
  }

  group('laska upgrade', () {
    test('moves the contract and the code of the service to the new version',
        () async {
      writeContract('proto', _contractV1);
      File('${workspace.path}/client.dart').writeAsStringSync('''
final path = '/v1/users/\$id';
final service = 'users.v1.UsersService';
''');

      final result = await _run(<String>[
        'upgrade',
        '--api',
        'users',
        '--from',
        'v1',
        '--to',
        'v2',
        '--path',
        workspace.path,
      ]);

      expect(result.code, 0, reason: result.err);

      final contract =
          File('${workspace.path}/proto/users.proto').readAsStringSync();
      expect(contract, contains('package users.v2;'));
      expect(contract, contains('"/v2/users/{id}"'));

      final client = File('${workspace.path}/client.dart').readAsStringSync();
      expect(client, contains("'/v2/users/\$id'"));
      expect(client, contains('users.v2.UsersService'));
    });

    test('writes nothing when it runs dry', () async {
      writeContract('proto', _contractV1);

      final result = await _run(<String>[
        'upgrade',
        '--api',
        'users',
        '--from',
        'v1',
        '--to',
        'v2',
        '--path',
        workspace.path,
        '--dry-run',
      ]);

      expect(result.code, 0, reason: result.err);
      expect(result.out, contains('would change'));

      final contract =
          File('${workspace.path}/proto/users.proto').readAsStringSync();
      expect(contract, contains('package users.v1;'));
    });

    test('refuses a version that does not change', () async {
      final result = await _run(<String>[
        'upgrade',
        '--api',
        'users',
        '--from',
        'v1',
        '--to',
        'v1',
        '--path',
        workspace.path,
      ]);

      expect(result.code, 64);
      expect(result.err, contains('does not change'));
    });

    test('refuses a call without the version of the API', () async {
      final result = await _run(<String>['upgrade', '--api', 'users']);

      expect(result.code, 64);
      expect(result.err, contains('--from'));
    });
  });

  group('the version of the API in the diff', () {
    test('refuses a breaking change that keeps the version of the API',
        () async {
      writeContract('base', _contractV1);
      writeContract('candidate', '''
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
  string id = 2;
}
''');

      final result = await _run(<String>[
        'contract',
        'diff',
        '--base',
        '${workspace.path}/base',
        '--candidate',
        '${workspace.path}/candidate',
      ]);

      expect(result.code, 1);
      expect(result.err, contains('users.v1'));
      expect(result.err, contains('v2'));
    });

    test('accepts a breaking change that goes to the next version', () async {
      writeContract('base', _contractV1);
      writeContract('candidate', _contractV2);

      final result = await _run(<String>[
        'contract',
        'diff',
        '--base',
        '${workspace.path}/base',
        '--candidate',
        '${workspace.path}/candidate',
      ]);

      expect(result.err, isNot(contains('must go from')));
    });
  });
}
