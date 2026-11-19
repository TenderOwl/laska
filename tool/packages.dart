import 'dart:io';

/// The packages of the workspace that are published on pub.dev.
///
/// The order is the order of the publication: a package is published after
/// the packages it depends on.
const List<String> publishedPackages = <String>[
  'laska_core',
  'laska_contracts',
  'laska_test',
  'laska_cli',
];

/// The members of the workspace, read from the `workspace:` list of the
/// `pubspec.yaml` of the root.
///
/// The gate of the repository walks this list, so a package that joins the
/// workspace is tested without a change of the gate. A list that is written
/// twice drifts from the workspace, and the drift is silent: the package that
/// is missing from the list is never tested.
List<String> workspaceMembers({Directory? root}) {
  final directory = root ?? Directory.current;
  final pubspec = File('${directory.path}/pubspec.yaml');
  if (!pubspec.existsSync()) {
    throw StateError('The pubspec of the root of the repository is not found.');
  }

  final members = <String>[];
  var inWorkspace = false;

  for (final line in pubspec.readAsLinesSync()) {
    if (!inWorkspace) {
      inWorkspace = line.startsWith('workspace:');
      continue;
    }
    if (line.trim().isEmpty) {
      continue;
    }
    if (!line.startsWith(' ') && !line.startsWith('\t')) {
      break;
    }
    final member = RegExp(r'^\s*-\s*(\S+)\s*$').firstMatch(line);
    if (member != null) {
      members.add(member.group(1)!);
    }
  }

  if (members.isEmpty) {
    throw StateError(
      'The list of the workspace of the pubspec of the root is empty.',
    );
  }
  return members;
}

/// The version of the package in the [directory].
///
/// The version is the one of the `version:` key of its pubspec.
String packageVersion(Directory directory) {
  final pubspec = File('${directory.path}/pubspec.yaml');
  if (!pubspec.existsSync()) {
    throw StateError('The pubspec of "${directory.path}" is not found.');
  }

  for (final line in pubspec.readAsLinesSync()) {
    final match = RegExp(r'^version:\s*(\S+)\s*$').firstMatch(line);
    if (match != null) {
      return match.group(1)!;
    }
  }

  throw StateError('The pubspec of "${directory.path}" holds no version.');
}
