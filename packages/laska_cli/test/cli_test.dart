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

Future<ProcessResult> _run(List<String> arguments) => Process.run(
      Platform.resolvedExecutable,
      <String>['run', 'bin/laska.dart', ...arguments],
      workingDirectory: Directory.current.path,
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
}
