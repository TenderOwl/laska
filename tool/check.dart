import 'dart:io';

import 'packages.dart';

/// Runs the repository checks: formatting, analysis, the versions of the
/// packages and the tests of every package of the workspace.
///
/// Usage: `dart run tool/check.dart`
Future<void> main() async {
  final root = Directory.current;

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

  if (!checkVersions(root)) {
    failed = true;
  }

  // The list of the tests is the list of the workspace, read from the pubspec
  // of the root: a package that joins the workspace is tested without a change
  // of this file.
  for (final package in workspaceMembers(root: root)) {
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

/// Checks that the published packages hold one version, and that the version
/// of the root of the repository is the same.
///
/// The packages of the workspace move in lockstep: a package that depends on
/// another one names a range of versions, and a version that drifts breaks the
/// publication — pub.dev refuses a package that depends on a version that is
/// not published yet.
///
/// Returns whether the versions agree.
bool checkVersions(Directory root) {
  stdout.writeln('==> versions');

  final versions = <String, String>{};
  for (final package in publishedPackages) {
    versions[package] = packageVersion(
      Directory('${root.path}/packages/$package'),
    );
  }

  final distinct = versions.values.toSet();
  if (distinct.length > 1) {
    stderr.writeln('FAILED: versions');
    versions.forEach((package, version) {
      stderr.writeln('  $package: $version');
    });
    stderr.writeln(
      'The published packages of the workspace have to hold one version.',
    );
    return false;
  }

  final version = distinct.single;

  final rootVersion = packageVersion(root);
  if (rootVersion != version) {
    stderr.writeln('FAILED: versions');
    stderr.writeln('  the root of the repository: $rootVersion');
    stderr.writeln('  the published packages: $version');
    stderr.writeln(
      'The version of the root of the repository has to be the version of the '
      'published packages.',
    );
    return false;
  }

  stdout.writeln('the packages of the workspace hold the version $version');
  return true;
}
