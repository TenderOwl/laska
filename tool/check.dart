import 'dart:io';

/// Runs the repository checks: formatting, analysis and the tests of every
/// package of the workspace.
///
/// Usage: `dart run tool/check.dart`
Future<void> main() async {
  final root = Directory.current;
  const packages = <String>[
    'packages/laska_core',
    'packages/laska_contracts',
    'packages/laska_cli',
    'packages/laska_test',
    'example/auth_service',
    'example/contract_slice',
    'example/database_service',
  ];

  var failed = false;

  Future<void> run(
    String label,
    List<String> arguments, {
    String? workingDirectory,
  }) async {
    stdout.writeln('==> $label');
    final result = await Process.run(
      Platform.resolvedExecutable,
      arguments,
      workingDirectory: workingDirectory ?? root.path,
    );
    stdout.write(result.stdout);
    stderr.write(result.stderr);
    if (result.exitCode != 0) {
      failed = true;
      stderr.writeln('FAILED: $label');
    }
  }

  await run(
    'format',
    <String>['format', '--output=none', '--set-exit-if-changed', '.'],
  );
  await run('analyze', <String>['analyze', '.']);

  for (final package in packages) {
    await run(
      'test: $package',
      <String>['test'],
      workingDirectory: '${root.path}/$package',
    );
  }

  if (failed) {
    stderr.writeln('Some checks failed.');
    exit(1);
  }
  stdout.writeln('All checks passed.');
}
