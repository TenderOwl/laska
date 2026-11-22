/// The compilation of a service into a single binary.
///
/// A service of Laska is a Dart program, so the Dart SDK compiles it into a
/// native binary: the binary holds the runtime, the service and its
/// dependencies, and it runs on a machine with no Dart SDK on it.
///
/// The files of the service are not part of the binary: the frontend of an app
/// and the SQL migrations of a service travel next to it.
library;

import 'dart:io';

import 'yaml.dart';

/// Raised when a service cannot be compiled.
class BuildException implements Exception {
  /// Creates an exception with [message].
  BuildException(this.message);

  /// Human readable description of the problem.
  final String message;

  @override
  String toString() => 'BuildException: $message';
}

/// The plan of the compilation of a service.
class BuildPlan {
  /// Creates a plan.
  const BuildPlan({
    required this.entrypoint,
    required this.output,
    required this.workingDirectory,
  });

  /// The Dart file of the service.
  final String entrypoint;

  /// The path of the binary.
  final String output;

  /// The directory the compilation runs in.
  ///
  /// It is the directory of the package of the service, so the compilation
  /// finds the configuration of the packages of the service.
  final String workingDirectory;
}

/// The result of the compilation of a service.
class BuildResult {
  /// Creates a result.
  const BuildResult({required this.output, required this.size});

  /// The path of the binary.
  final String output;

  /// The size of the binary in bytes.
  final int size;

  /// The size of the binary, as a human readable string.
  String get readableSize {
    const List<String> units = <String>['B', 'kB', 'MB', 'GB'];
    var size = this.size.toDouble();
    var unit = 0;

    while (size >= 1024 && unit < units.length - 1) {
      size /= 1024;
      unit++;
    }

    final value = unit == 0 ? size.toStringAsFixed(0) : size.toStringAsFixed(1);
    return '$value ${units[unit]}';
  }
}

/// The plan of the compilation of the service of the package [directory].
///
/// The [entrypoint] is the Dart file of the service. It is `bin/server.dart`
/// when it is not given, and `bin/main.dart` when the package holds no
/// server. The plan fails when the package holds no entrypoint at all.
///
/// The binary is written to [output], and to the `build` directory of the
/// package when it is not given. A relative path is read against the package,
/// so the binary lands in the package it belongs to.
BuildPlan planOfBuild(
  Directory directory, {
  String? entrypoint,
  String? output,
}) {
  final root = _normalize(directory.absolute.path);

  final source = _entrypointOf(root, entrypoint);
  if (source == null) {
    throw BuildException(
      'No entrypoint found in "$root". Pass --entrypoint with the Dart '
      'file of the service.',
    );
  }

  final name = _packageNameOf(root);
  final separator = Platform.pathSeparator;
  final buildDirectory = 'build';
  final target = output == null
      ? _normalize(
          '$root$separator$buildDirectory$separator$name${_executableSuffix()}')
      : (File(output).isAbsolute
          ? _normalize(output)
          : _normalize('$root$separator$output'));

  return BuildPlan(
    entrypoint: source,
    output: target,
    workingDirectory: root,
  );
}

/// Compiles the service of the [plan] into a single binary.
///
/// The [dartExecutable] is the Dart SDK that compiles the service. The SDK of
/// the running process is used when it is not given, and the path is looked
/// through when the process is not the SDK itself.
Future<BuildResult> compileService(
  BuildPlan plan, {
  String? dartExecutable,
}) async {
  final dart = dartExecutable ?? findDartExecutable();
  if (dart == null) {
    throw BuildException(
      'The Dart SDK is needed to compile a service, and it was not found. '
      'Pass --dart with the path of the "dart" command.',
    );
  }

  final output = File(plan.output);
  // The compiler does not create the directory of the binary, so it is
  // created here: a build of a fresh package fails otherwise.
  await output.parent.create(recursive: true);

  final result = await Process.run(
    dart,
    <String>['compile', 'exe', plan.entrypoint, '-o', plan.output],
    workingDirectory: plan.workingDirectory,
  );

  if (result.exitCode != 0) {
    final error = result.stderr.toString().trim();
    final message = result.stdout.toString().trim();
    throw BuildException(error.isEmpty ? message : error);
  }

  return BuildResult(output: plan.output, size: output.lengthSync());
}

/// The path of the Dart SDK, or `null` when it is not found.
///
/// The SDK of the running process is the SDK itself when the CLI runs from the
/// source. A compiled CLI looks for the SDK in the path of the process.
String? findDartExecutable() {
  final resolved = Platform.resolvedExecutable;
  if (_isDart(resolved)) {
    return resolved;
  }

  final path = Platform.environment['PATH'];
  if (path == null) {
    return null;
  }

  final separator = Platform.isWindows ? ';' : ':';
  for (final directory in path.split(separator)) {
    if (directory.isEmpty) {
      continue;
    }
    for (final candidate in Platform.isWindows
        ? const <String>['dart.exe', 'dart.bat']
        : const <String>['dart']) {
      final file = File('$directory${Platform.pathSeparator}$candidate');
      if (file.existsSync()) {
        return file.path;
      }
    }
  }

  return null;
}

/// The entrypoint of the package [root].
///
/// The [entrypoint] is the file the caller named, and `bin/server.dart` or
/// `bin/main.dart` when it is not named. The value is `null` when the package
/// holds no entrypoint.
String? _entrypointOf(String root, String? entrypoint) {
  final separator = Platform.pathSeparator;

  if (entrypoint != null) {
    final file = File(entrypoint);
    final path = file.isAbsolute ? file.path : '$root$separator$entrypoint';
    if (!File(path).existsSync()) {
      throw BuildException('The entrypoint "$entrypoint" does not exist.');
    }
    return path;
  }

  for (final candidate in const <String>['bin/server.dart', 'bin/main.dart']) {
    final file = File('$root$separator$candidate');
    if (file.existsSync()) {
      return file.path;
    }
  }

  return null;
}

/// The name of the package in the directory [root].
///
/// The name of the `pubspec.yaml` is the name of the package, and the name of
/// the directory is the name of the package when it holds no pubspec.
String _packageNameOf(String root) {
  final separator = Platform.pathSeparator;
  final file = File('$root$separator' 'pubspec.yaml');
  if (file.existsSync()) {
    try {
      final document = parseYaml(file.readAsStringSync());
      if (document is Map) {
        final name = document['name'];
        if (name is String && name.isNotEmpty) {
          return name.replaceAll(RegExp(r'[^A-Za-z0-9_.-]'), '_');
        }
      }
    } on YamlException {
      // The name of the directory is used when the pubspec cannot be read.
    }
  }

  final path = root;
  final index = path.lastIndexOf(Platform.pathSeparator);
  return index < 0 ? path : path.substring(index + 1);
}

/// Whether the path [path] is the path of the Dart SDK.
bool _isDart(String path) {
  final separator = path.lastIndexOf(Platform.pathSeparator);
  final name =
      (separator < 0 ? path : path.substring(separator + 1)).toLowerCase();
  return name == 'dart' || name == 'dart.exe';
}

/// The suffix of the binary of the platform.
String _executableSuffix() => Platform.isWindows ? '.exe' : '';

/// The path [path] without the `.` of its parts.
///
/// The paths of the commands are read against the directory they name, so a
/// path that holds a `.` is cleaned up before it is shown or written.
String _normalize(String path) => path
    .replaceAll(RegExp(r'[\\/]\.(?=[\\/]|$)'), '')
    .replaceAll(RegExp(r'[\\/]+'), Platform.pathSeparator);
