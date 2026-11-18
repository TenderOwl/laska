import 'dart:io';

import 'package:laska_contracts/laska_contracts.dart';

/// The codemods of the steps of the framework.
///
/// The registry holds one entry per step that changes the source of a
/// service. A step that only adds something needs no codemod and is not
/// listed, so the registry is empty while the framework adds and never
/// breaks.
const List<FrameworkCodemod> frameworkCodemods = <FrameworkCodemod>[];

/// A codemod of one step of the framework.
class FrameworkCodemod extends Codemod {
  /// Creates a codemod.
  const FrameworkCodemod({
    required super.id,
    required super.description,
    required super.rules,
    required this.from,
    required this.to,
  });

  /// The version the step starts at.
  final Version from;

  /// The version the step brings the service to.
  final Version to;
}

/// The codemods of the step from the version [from] to the version [to].
///
/// The list is empty when the step needs no rewrite of the source, e.g. when
/// the step only adds something.
List<FrameworkCodemod> frameworkCodemodsBetween(String from, String to) {
  final start = Version.tryParse(from);
  final end = Version.tryParse(to);
  if (start == null || end == null) {
    return const <FrameworkCodemod>[];
  }

  return frameworkCodemods
      .where((codemod) => codemod.from == start && codemod.to == end)
      .toList(growable: false);
}

/// One rewrite of the source of a service.
class CodemodRule {
  /// Creates a rule.
  const CodemodRule({
    required this.pattern,
    required this.replacement,
    required this.description,
  });

  /// The pattern the rule looks for.
  final Pattern pattern;

  /// What the rule writes instead of the match.
  final String replacement;

  /// What the rule does, in words.
  final String description;
}

/// A group of the rewrites that belong together.
///
/// A codemod is one step of the upgrade of a service: the steps of the
/// framework are shipped with the CLI, and a service may add its own.
class Codemod {
  /// Creates a codemod.
  const Codemod({
    required this.id,
    required this.description,
    required this.rules,
  });

  /// The id of the codemod, e.g. `api-version`.
  final String id;

  /// What the codemod does, in words.
  final String description;

  /// The rewrites of the codemod.
  final List<CodemodRule> rules;
}

/// The codemod that moves the API [api] from the version [from] to the
/// version [to].
///
/// The version of the API lives in the name of the package of the `.proto`
/// file and in the paths of the REST projection, so the contract, the
/// generated code and the calls of the service follow the new version
/// together.
Codemod apiVersionCodemod({
  required String api,
  required String from,
  required String to,
}) {
  final escapedApi = RegExp.escape(api);
  final escapedFrom = RegExp.escape(from);

  return Codemod(
    id: 'api-version',
    description: 'Move the API "$api" from $from to $to.',
    rules: <CodemodRule>[
      CodemodRule(
        pattern: RegExp('package\\s+$escapedApi\\.$escapedFrom\\b'),
        replacement: 'package $api.$to',
        description: 'the package of the contract',
      ),
      CodemodRule(
        pattern: RegExp('"/$escapedFrom/'),
        replacement: '"/$to/',
        description: 'the path of the REST projection',
      ),
      CodemodRule(
        pattern: RegExp("'/$escapedFrom/"),
        replacement: "'/$to/",
        description: 'the path of the call of a client',
      ),
      CodemodRule(
        pattern: RegExp('\\b$escapedApi\\.$escapedFrom\\.'),
        replacement: '$api.$to.',
        description: 'the name of the service in the contract',
      ),
    ],
  );
}

/// The result of an upgrade.
class UpgradeResult {
  /// Creates a result.
  const UpgradeResult({required this.changedFiles, required this.notes});

  /// The files the upgrade wrote.
  final List<String> changedFiles;

  /// What the upgrade did, one line per change.
  final List<String> notes;
}

/// The directories the upgrade does not touch.
const List<String> _skippedDirectories = <String>[
  '.dart_tool',
  '.git',
  'build',
  'node_modules',
];

/// Applies the [codemods] to the files of the [directory].
///
/// The files that are written are the `.proto` and the `.dart` files. When
/// [dryRun] is set, the files are not written, so the user sees what the
/// upgrade would do.
Future<UpgradeResult> applyCodemods(
  Directory directory,
  List<Codemod> codemods, {
  bool dryRun = false,
}) async {
  final changedFiles = <String>[];
  final notes = <String>[];

  for (final file in _sourceFilesOf(directory)) {
    final original = file.readAsStringSync();
    var content = original;

    for (final codemod in codemods) {
      for (final rule in codemod.rules) {
        content = content.replaceAllMapped(
          rule.pattern,
          (match) => rule.replacement,
        );
      }
    }

    if (content == original) {
      continue;
    }

    if (!dryRun) {
      file.writeAsStringSync(content);
    }

    changedFiles.add(file.path);
    notes.add('${file.path}: ${codemods.map((c) => c.description).join(', ')}');
  }

  return UpgradeResult(changedFiles: changedFiles, notes: notes);
}

/// The source files of the [directory].
List<File> _sourceFilesOf(Directory directory) {
  if (!directory.existsSync()) {
    return const <File>[];
  }

  final files = <File>[];
  for (final entity
      in directory.listSync(recursive: true, followLinks: false)) {
    if (entity is! File) {
      continue;
    }

    final path = entity.path.replaceAll('\\', '/');
    if (_skippedDirectories.any((name) => path.contains('/$name/'))) {
      continue;
    }

    final extension = entity.path.split('.').last.toLowerCase();
    if (extension != 'dart' && extension != 'proto') {
      continue;
    }

    files.add(entity);
  }

  files.sort((left, right) => left.path.compareTo(right.path));
  return files;
}
