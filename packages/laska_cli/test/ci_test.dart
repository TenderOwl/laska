import 'dart:io';

import 'package:laska_cli/src/ci.dart';
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

void main() {
  late Directory workspace;

  setUp(() {
    workspace = Directory.systemTemp.createTempSync('laska_ci_test');
  });

  tearDown(() {
    if (workspace.existsSync()) {
      workspace.deleteSync(recursive: true);
    }
  });

  void writeContract(String source) {
    final directory = Directory('${workspace.path}/api')
      ..createSync(recursive: true);
    File('${directory.path}/users.proto').writeAsStringSync(source);
  }

  group('laska contract lint', () {
    test('accepts a contract that follows the rules', () async {
      writeContract('''
syntax = "proto3";

package users.v1;

message User {
  string id = 1;
}
''');

      final result = await _run(<String>[
        'contract',
        'lint',
        '--proto',
        '${workspace.path}/api',
      ]);

      expect(result.code, 0);
      expect(result.out, contains('No problem found'));
    });

    test('fails when the contract breaks a rule', () async {
      writeContract('''
syntax = "proto3";

package users.v1;

message user_profile {
  string id = 1;
}
''');

      final result = await _run(<String>[
        'contract',
        'lint',
        '--proto',
        '${workspace.path}/api',
      ]);

      expect(result.code, 1);
      expect(result.out, contains('PascalCase'));
      expect(result.out, contains('1 problem(s) found'));
    });

    test('fails when there is no contract', () async {
      final result = await _run(<String>[
        'contract',
        'lint',
        '--proto',
        '${workspace.path}/missing',
      ]);

      expect(result.code, 66);
      expect(result.err, contains('No .proto files found'));
    });
  });

  group('laska ci:recipe', () {
    test('writes a workflow that runs the checks', () async {
      final result = await _run(<String>[
        'ci:recipe',
        '--out',
        '${workspace.path}/.github/workflows/laska.yml',
        '--proto',
        'api',
      ]);

      expect(result.code, 0);

      final recipe = File('${workspace.path}/.github/workflows/laska.yml')
          .readAsStringSync();

      expect(recipe, contains('name: laska'));
      expect(recipe, contains('dart analyze'));
      expect(recipe, contains('dart test'));
      expect(recipe, contains('contract lint --proto api'));
      expect(recipe, isNot(contains('contract diff')));
    });

    test('adds the comparison of the contracts when it is given', () async {
      await _run(<String>[
        'ci:recipe',
        '--out',
        '${workspace.path}/laska.yml',
        '--base',
        'contracts/v1',
        '--candidate',
        'contracts/v2',
      ]);

      final recipe = File('${workspace.path}/laska.yml').readAsStringSync();

      expect(
        recipe,
        contains('contract diff --base contracts/v1 --candidate contracts/v2'),
      );
    });
  });

  group('renderCiRecipe', () {
    test('holds the steps of the pipeline', () {
      final recipe = renderCiRecipe();

      expect(
          recipe, contains('dart format --output=none --set-exit-if-changed'));
      expect(recipe, contains('dart analyze'));
      expect(recipe, contains('dart test'));
      expect(recipe, contains('actions/checkout@v4'));
      expect(recipe, contains('dart-lang/setup-dart@v1'));
    });
  });
}
