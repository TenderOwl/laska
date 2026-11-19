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
    String? executable,
  }) async {
    stdout.writeln('==> $label');
    final result = await Process.run(
      executable ?? Platform.resolvedExecutable,
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

  if (!checkCliVersion(root)) {
    failed = true;
  }

  if (!checkPublication(root)) {
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

  // The SDK of the example is written in Go, so it is tested with the
  // toolchain of Go. The gate of the repository runs the tests of every
  // language the framework speaks, and the toolchain of Go is skipped when it
  // is not installed.
  final go = _executableOnPath('go');
  if (go == null) {
    stdout.writeln(
      'the toolchain of Go is not installed: the tests of the Go SDK are '
      'skipped',
    );
  } else {
    final sdk = '${root.path}/example/contract_slice/go';

    final gofmt = _executableOnPath('gofmt') ?? 'gofmt';
    if (!checkGoFormat(gofmt, sdk)) {
      failed = true;
    }

    await run(
      'vet: the Go SDK',
      <String>['vet', './...'],
      workingDirectory: sdk,
      executable: go,
    );
    await run(
      'test: the Go SDK',
      <String>['test', './...'],
      workingDirectory: sdk,
      executable: go,
    );
  }

  if (failed) {
    stderr.writeln('Some checks failed.');
    exit(1);
  }
  stdout.writeln('All checks passed.');
}

/// Checks that the Go code of the SDK in [directory] is formatted.
///
/// The formatter prints the files that are not formatted, so the check reads
/// what it prints instead of its exit code.
bool checkGoFormat(String gofmt, String directory) {
  stdout.writeln('==> format: the Go SDK');

  final result = Process.runSync(
    gofmt,
    <String>['-l', '.'],
    workingDirectory: directory,
  );
  stdout.write(result.stdout);
  stderr.write(result.stderr);

  if (result.exitCode != 0) {
    stderr.writeln('FAILED: format: the Go SDK');
    return false;
  }

  final files = '${result.stdout}'.trim();
  if (files.isNotEmpty) {
    stderr.writeln('FAILED: format: the Go SDK');
    stderr.writeln('  the files that are not formatted:');
    for (final file in files.split('\n')) {
      stderr.writeln('    $file');
    }
    return false;
  }

  stdout.writeln('the Go SDK is formatted');
  return true;
}

/// Finds the program [name] on the path of the system.
///
/// Returns `null` when the program is not installed.
String? _executableOnPath(String name) {
  final path = Platform.environment['PATH'] ?? '';
  final separator = Platform.isWindows ? ';' : ':';
  final extensions = Platform.isWindows
      ? const <String>['.exe', '.bat', '.cmd', '']
      : const <String>[''];

  for (final directory in path.split(separator)) {
    final trimmed = directory.trim();
    if (trimmed.isEmpty) {
      continue;
    }
    for (final extension in extensions) {
      final candidate =
          File('$trimmed${Platform.pathSeparator}$name$extension');
      if (candidate.existsSync()) {
        return candidate.path;
      }
    }
  }
  return null;
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

/// Checks that the version of the command line interface is written in the code
/// the same way it is written in the pubspec.
///
/// The command prints the version and writes it into the projects it
/// scaffolds, and the version of the command is the version of the framework:
/// the packages move in lockstep. The constant that holds it cannot be read
/// from the pubspec at runtime in every way the command is run — the bundle of
/// the release carries the code and not the pubspec — so the gate holds the
/// two together.
///
/// Returns whether the versions agree.
bool checkCliVersion(Directory root) {
  stdout.writeln('==> the version of the command');

  final directory = Directory('${root.path}/packages/laska_cli');
  final version = packageVersion(directory);

  final file = File('${directory.path}/lib/src/version.dart');
  if (!file.existsSync()) {
    stderr.writeln('FAILED: the version of the command');
    stderr.writeln('  the package "laska_cli" has no "lib/src/version.dart".');
    return false;
  }

  final match = RegExp(
    r"laskaVersion\s*=\s*'([^']+)'",
  ).firstMatch(file.readAsStringSync());
  if (match == null) {
    stderr.writeln('FAILED: the version of the command');
    stderr.writeln('  "lib/src/version.dart" holds no version.');
    return false;
  }

  final constant = match.group(1)!;
  if (constant != version) {
    stderr.writeln('FAILED: the version of the command');
    stderr.writeln('  the pubspec of "laska_cli": $version');
    stderr.writeln('  the constant of "lib/src/version.dart": $constant');
    stderr.writeln(
      'The version of the command and the version of its pubspec have to be '
      'the same one.',
    );
    return false;
  }

  stdout.writeln('the command holds the version $version');
  return true;
}

/// Checks that the published packages are ready to be published on pub.dev.
///
/// The check reads the files of the packages, so it does not depend on the
/// versions that are already on pub.dev: a package that needs a new version
/// of another package of the workspace does not break the gate of the
/// repository before it is released.
///
/// The dry run of the client (`dart run tool/publish.dart --all --dry-run`)
/// checks the rest — the archive, the size and the warnings of pub.dev — and
/// is run before a release.
///
/// Returns whether the packages are ready.
bool checkPublication(Directory root) {
  stdout.writeln('==> publication');

  final problems = <String>[];

  for (final package in publishedPackages) {
    final directory = Directory('${root.path}/packages/$package');

    for (final file in const <String>['LICENSE', 'README.md', 'CHANGELOG.md']) {
      if (!File('${directory.path}/$file').existsSync()) {
        problems.add('The package "$package" has no "$file".');
      }
    }

    final pubspec = File('${directory.path}/pubspec.yaml');
    if (!pubspec.existsSync()) {
      problems.add('The package "$package" has no pubspec.');
      continue;
    }

    final lines = pubspec.readAsLinesSync();
    for (final key in const <String>['name:', 'version:', 'description:']) {
      if (!lines.any((line) => line.startsWith(key))) {
        problems.add('The pubspec of "$package" has no "$key".');
      }
    }
    if (lines.any((line) => line.trim() == 'publish_to: none')) {
      problems.add('The package "$package" is marked as "publish_to: none".');
    }
    for (final line in lines) {
      final trimmed = line.trim();
      if (trimmed.startsWith('path:') || trimmed.contains('{path:')) {
        problems.add(
          'The pubspec of "$package" holds a path dependency ("$trimmed"); '
          'pub.dev does not accept them.',
        );
      }
    }
  }

  if (problems.isNotEmpty) {
    stderr.writeln('FAILED: publication');
    for (final problem in problems) {
      stderr.writeln('  $problem');
    }
    return false;
  }

  stdout.writeln('the packages of the workspace are ready to be published');
  return true;
}
