import 'dart:io';

/// Publishes the packages of the workspace to pub.dev.
///
/// The packages of the workspace carry `resolution: workspace`, and a package
/// of a workspace cannot be published with it: the line has to go. The script
/// copies the package into a temporary directory, takes the line out of the
/// pubspec and runs `dart pub publish` there.
///
/// The tree of the repository has to be clean, because the files that are
/// published are the files that are committed. The check may be skipped with
/// `--allow-dirty`, and then the copy of the package is published as it is.
///
/// The packages are published in the order of their dependencies: `laska_core`
/// first, then `laska_contracts`, `laska_test` and `laska_cli`.
///
/// The token of the publisher is read from the environment `PUB_TOKEN`, so a
/// pipeline may publish without a person in the loop.
///
/// Usage:
///   dart run tool/publish.dart --package laska_core [--dry-run]
///   dart run tool/publish.dart --all [--dry-run]
Future<void> main(List<String> arguments) async {
  final options = _Options.parse(arguments);

  if (!options.allowDirty && !_treeIsClean()) {
    stderr.writeln(
      'The tree of the repository holds changes, so the published files and '
      'the committed files would differ. Commit them, or run the command '
      'with --allow-dirty.',
    );
    exit(1);
  }

  final packages = options.all ? _packages : options.packages;
  if (packages.isEmpty) {
    stderr.writeln('Nothing to publish. Pass --package or --all.');
    exit(64);
  }

  for (final package in packages) {
    final directory = Directory('packages/$package');
    if (!directory.existsSync()) {
      stderr.writeln('The package "$package" is not in the workspace.');
      exit(66);
    }

    stdout.writeln('==> $package');
    final staged =
        _stage(directory, localDependencies: options.localDependencies);
    try {
      final code = await _publish(staged, dryRun: options.dryRun);
      if (code != 0) {
        stderr.writeln('FAILED: $package');
        exit(code);
      }
    } finally {
      staged.deleteSync(recursive: true);
    }
  }

  stdout.writeln(
    options.dryRun
        ? 'The dry run is over: every package is ready to be published.'
        : 'The packages are published.',
  );
}

/// The options of the command.
class _Options {
  _Options({
    required this.packages,
    required this.all,
    required this.dryRun,
    required this.allowDirty,
    required this.localDependencies,
  });

  /// The packages that were named one by one.
  final List<String> packages;

  /// Whether every package of the workspace is published.
  final bool all;

  /// Whether the command only checks the packages.
  final bool dryRun;

  /// Whether the tree of the repository may hold changes.
  final bool allowDirty;

  /// Whether the dependencies on the packages of the workspace are local.
  ///
  /// The option lets the files of a package be checked before its
  /// dependencies are published: the resolution then uses the packages of the
  /// workspace instead of the ones of pub.dev.
  final bool localDependencies;

  /// Reads the options out of the [arguments].
  static _Options parse(List<String> arguments) {
    final packages = <String>[];
    var all = false;
    var dryRun = false;
    var allowDirty = false;
    var localDependencies = false;

    for (var index = 0; index < arguments.length; index++) {
      final argument = arguments[index];
      switch (argument) {
        case '--package':
          index++;
          if (index >= arguments.length) {
            stderr.writeln('The option --package needs the name of a package.');
            exit(64);
          }
          packages.add(arguments[index]);
        case '--all':
          all = true;
        case '--dry-run':
          dryRun = true;
        case '--allow-dirty':
          allowDirty = true;
        case '--local-dependencies':
          localDependencies = true;
        default:
          stderr.writeln('Unknown option "$argument".');
          exit(64);
      }
    }

    return _Options(
      packages: packages,
      all: all,
      dryRun: dryRun,
      allowDirty: allowDirty,
      localDependencies: localDependencies,
    );
  }
}

/// The packages of the workspace, in the order they are published.
const List<String> _packages = <String>[
  'laska_core',
  'laska_contracts',
  'laska_test',
  'laska_cli',
];

/// Whether the tree of the repository holds no change.
bool _treeIsClean() {
  final result = Process.runSync(
    'git',
    <String>['status', '--porcelain'],
  );
  if (result.exitCode != 0) {
    // The tree is not a tree of git, so there is nothing to check.
    return true;
  }
  return (result.stdout as String).trim().isEmpty;
}

/// Copies the [directory] of a package into a temporary directory.
///
/// The copy holds the files that are published, without the `resolution:
/// workspace` line of the pubspec: a package of a workspace cannot be
/// published with it.
Directory _stage(
  Directory directory, {
  required bool localDependencies,
}) {
  final staged = Directory.systemTemp.createTempSync('laska_publish_');

  for (final entity
      in directory.listSync(recursive: true, followLinks: false)) {
    if (entity is! File) {
      continue;
    }

    final relative = _relative(directory, entity);
    if (relative.startsWith('.dart_tool') ||
        relative.startsWith('build') ||
        relative.startsWith('pubspec.lock')) {
      continue;
    }

    final target = File('${staged.path}/$relative');
    target.parent.createSync(recursive: true);
    target.writeAsBytesSync(entity.readAsBytesSync());
  }

  final pubspec = File('${staged.path}/pubspec.yaml');
  final lines = pubspec
      .readAsLinesSync()
      .where((line) => line.trim() != 'resolution: workspace')
      .toList();
  pubspec.writeAsStringSync('${lines.join('\n')}\n');

  if (localDependencies) {
    _useLocalDependencies(staged);
  }

  return staged;
}

/// Points the dependencies on the packages of the workspace to the workspace.
///
/// The check of the files of a package may then run before its dependencies
/// are published.
void _useLocalDependencies(Directory staged) {
  final root = Directory.current.absolute.path.replaceAll('\\', '/');
  final pubspec = File('${staged.path}/pubspec.yaml');

  final rewritten = pubspec.readAsLinesSync().map((line) {
    for (final package in _packages) {
      if (line.startsWith('  $package: ^')) {
        return '  $package: {path: $root/packages/$package}';
      }
    }
    return line;
  }).toList();

  pubspec.writeAsStringSync('${rewritten.join('\n')}\n');
}

/// The path of the [file] relative to the [directory].
String _relative(Directory directory, File file) {
  final root = directory.absolute.path;
  final path = file.absolute.path;
  if (!path.startsWith(root)) {
    return path;
  }
  return path.substring(root.length + 1).replaceAll('\\', '/');
}

/// Runs `dart pub publish` in the [directory].
Future<int> _publish(Directory directory, {required bool dryRun}) async {
  final arguments = <String>[
    'pub',
    'publish',
    if (dryRun) '--dry-run',
  ];

  final process = await Process.start(
    Platform.resolvedExecutable,
    arguments,
    workingDirectory: directory.path,
    mode: ProcessStartMode.inheritStdio,
  );

  return process.exitCode;
}
