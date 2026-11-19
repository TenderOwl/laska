import 'dart:io';

import 'package:pub_semver/pub_semver.dart';

import 'yaml.dart';

/// The version of the language the code of the package in [directory] is
/// written for.
///
/// The version is the lower bound of the `sdk:` constraint of the pubspec of
/// the package: it is the version the code has to work with, and it is the
/// version `dart format` uses to pick the style of the formatter.
///
/// Returns `null` when there is no pubspec, or when it holds no constraint
/// that can be read.
Version? sdkVersionOf(String directory) {
  final pubspec = _pubspecOf(directory);
  if (pubspec == null) {
    return null;
  }

  final document = parseYaml(pubspec.readAsStringSync());
  if (document is! Map) {
    return null;
  }
  final environment = document['environment'];
  if (environment is! Map) {
    return null;
  }
  final constraint = environment['sdk'];
  if (constraint is! String) {
    return null;
  }

  try {
    final parsed = VersionConstraint.parse(constraint);
    if (parsed is Version) {
      return parsed;
    }
    if (parsed is VersionRange) {
      return parsed.min;
    }
    return null;
  } on FormatException {
    return null;
  }
}

/// The pubspec of the package that holds the [directory].
///
/// The directories above the directory are searched, so the version of the
/// package is found from any directory inside it.
File? _pubspecOf(String directory) {
  var current = Directory(directory).absolute;

  while (true) {
    final pubspec = File('${current.path}/pubspec.yaml');
    if (pubspec.existsSync()) {
      return pubspec;
    }
    final parent = current.parent;
    if (parent.path == current.path) {
      return null;
    }
    current = parent;
  }
}
