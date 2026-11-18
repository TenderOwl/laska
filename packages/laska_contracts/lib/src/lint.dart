/// The rules a contract follows.
///
/// The linter reads a contract the way a reviewer reads it: the naming, the
/// package layout and the version of the package. The rules are the ones the
/// framework itself follows, so a contract that passes the linter generates
/// the code the framework expects.
library;

import 'model.dart';
import 'naming.dart';

/// A problem of a contract.
class LintProblem {
  /// Creates a problem in [file] about [subject].
  LintProblem({
    required this.file,
    required this.subject,
    required this.message,
  });

  /// The file the problem was found in.
  final String file;

  /// What the problem is about, e.g. the name of a message.
  final String subject;

  /// Human readable description of the problem.
  final String message;

  @override
  String toString() => '$file: $subject: $message';
}

/// The rules of the contracts of Laska:
///
/// * the package is versioned, e.g. `users.v1`, and it matches the name of
///   the file;
/// * the messages, the enums and the services are written in PascalCase and
///   the services end with `Service`;
/// * the fields are written in snake_case and the values of the enums in
///   UPPER_SNAKE_CASE;
/// * the methods are written in PascalCase.
List<LintProblem> lintContract(Contract contract) {
  final problems = <LintProblem>[];

  for (final file in contract.files) {
    problems.addAll(_lintFile(file));
  }

  return problems;
}

/// The problems of one file of the contract.
List<LintProblem> _lintFile(ProtoFile file) {
  final problems = <LintProblem>[];

  if (file.package.isEmpty) {
    problems.add(
      LintProblem(
        file: file.path,
        subject: 'package',
        message: 'The file has no package. A contract is versioned, e.g. '
            '"users.v1".',
      ),
    );
  } else {
    if (!_isVersionedPackage(file.package)) {
      problems.add(
        LintProblem(
          file: file.path,
          subject: file.package,
          message: 'The package is not versioned. A contract is versioned, '
              'e.g. "users.v1".',
        ),
      );
    }

    final expected = _expectedFileName(file.package);
    final actual = _fileName(file.path);
    if (expected != null && actual != expected) {
      problems.add(
        LintProblem(
          file: file.path,
          subject: file.package,
          message: 'The package "$file.package" expects a file called '
              '"$expected.proto", but the file is called "$actual.proto".',
        ),
      );
    }
  }

  for (final message in file.messages) {
    if (!isPascalCase(message.name)) {
      problems.add(
        LintProblem(
          file: file.path,
          subject: message.fullName,
          message: 'A message is written in PascalCase.',
        ),
      );
    }

    for (final field in message.fields) {
      if (!isSnakeCase(field.name)) {
        problems.add(
          LintProblem(
            file: file.path,
            subject: '${message.fullName}.${field.name}',
            message: 'A field is written in snake_case.',
          ),
        );
      }
    }
  }

  for (final enumType in file.enums) {
    if (!isPascalCase(enumType.name)) {
      problems.add(
        LintProblem(
          file: file.path,
          subject: enumType.fullName,
          message: 'An enum is written in PascalCase.',
        ),
      );
    }

    for (final value in enumType.values) {
      if (!isUpperSnakeCase(value.name)) {
        problems.add(
          LintProblem(
            file: file.path,
            subject: '${enumType.fullName}.${value.name}',
            message: 'A value of an enum is written in UPPER_SNAKE_CASE.',
          ),
        );
      }
    }
  }

  for (final service in file.services) {
    if (!isPascalCase(service.name)) {
      problems.add(
        LintProblem(
          file: file.path,
          subject: service.fullName,
          message: 'A service is written in PascalCase.',
        ),
      );
    }

    if (!service.name.endsWith('Service')) {
      problems.add(
        LintProblem(
          file: file.path,
          subject: service.fullName,
          message: 'A service ends with "Service".',
        ),
      );
    }

    for (final method in service.methods) {
      if (!isPascalCase(method.name)) {
        problems.add(
          LintProblem(
            file: file.path,
            subject: '${service.fullName}.${method.name}',
            message: 'A method is written in PascalCase.',
          ),
        );
      }
    }
  }

  return problems;
}

/// Whether the package carries a version, e.g. `users.v1`.
bool _isVersionedPackage(String package) {
  final parts = package.split('.');
  if (parts.length < 2) {
    return false;
  }
  return RegExp(r'^v[0-9]+$').hasMatch(parts.last);
}

/// The name of the file the package expects, e.g. `users` for `users.v1`.
String? _expectedFileName(String package) {
  final parts = package.split('.');
  if (parts.length < 2) {
    return null;
  }
  return parts.take(parts.length - 1).join('.');
}

/// The name of the file, without its directory and its extension.
String _fileName(String path) {
  final name = path.replaceAll('\\', '/').split('/').last;
  return name.endsWith('.proto')
      ? name.substring(0, name.length - '.proto'.length)
      : name;
}
