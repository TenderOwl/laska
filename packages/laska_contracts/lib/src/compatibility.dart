/// The compatibility matrix of the versions of a contract.
///
/// The matrix answers the question a release manager asks: "which clients
/// work against which servers?". The answer is computed out of the contracts
/// themselves, so it cannot drift away from the code the services run.
///
/// The analysis is directional. A client is the code that calls, a server is
/// the code that answers, and the two are not interchangeable: a client of the
/// old version keeps working against a server that only added something, while
/// a client of the new version cannot call a method the old server does not
/// have.
library;

import 'model.dart';

/// How well a client works against a server.
enum Compatibility {
  /// The client works against the server as it is.
  compatible,

  /// The client works, but the server lacks a part of what the client expects.
  ///
  /// The calls the client makes to the parts the server still has keep
  /// working; the missing ones fail.
  partial,

  /// The client cannot work against the server.
  incompatible,
}

/// The kind of a difference between a client and a server.
enum CompatibilityIssueKind {
  /// The server does not have the service the client calls.
  missingService,

  /// The server does not have the method the client calls.
  missingMethod,

  /// The server does not have the message the client expects.
  missingMessage,

  /// The server does not have the field the client expects.
  missingField,

  /// The request of the method changed.
  changedRequestType,

  /// The response of the method changed.
  changedResponseType,

  /// The type of a field changed.
  changedFieldType,

  /// The number of a field on the wire changed.
  changedFieldNumber,

  /// The label of a field changed, e.g. it became repeated.
  changedFieldLabel,

  /// The REST binding of the method changed.
  changedPath,
}

/// A difference between a client and a server.
class CompatibilityIssue {
  /// Creates an issue.
  CompatibilityIssue({
    required this.kind,
    required this.subject,
    required this.message,
  });

  /// The kind of the difference.
  final CompatibilityIssueKind kind;

  /// What the difference is about, e.g. `users.GetUser`.
  final String subject;

  /// A description of the difference.
  final String message;

  /// Whether the difference keeps the client from working at all.
  ///
  /// A missing method or a missing field only breaks the calls that need it,
  /// while a changed type or a changed number breaks the wire itself.
  bool get isFatal => switch (kind) {
        CompatibilityIssueKind.missingService => true,
        CompatibilityIssueKind.missingMessage => true,
        CompatibilityIssueKind.changedRequestType => true,
        CompatibilityIssueKind.changedResponseType => true,
        CompatibilityIssueKind.changedFieldType => true,
        CompatibilityIssueKind.changedFieldNumber => true,
        CompatibilityIssueKind.changedFieldLabel => true,
        CompatibilityIssueKind.missingMethod => false,
        CompatibilityIssueKind.missingField => false,
        CompatibilityIssueKind.changedPath => false,
      };

  @override
  String toString() => '$subject: $message';
}

/// What a client and a server need from each other.
class CompatibilityReport {
  /// Creates a report.
  CompatibilityReport({
    required this.compatibility,
    required this.issues,
    required this.pathIssues,
  });

  /// How well the client works against the server.
  final Compatibility compatibility;

  /// The differences that are not about the REST bindings.
  final List<CompatibilityIssue> issues;

  /// The differences in the REST bindings of the methods.
  ///
  /// A version of an API lives in the paths of its REST projection, so the
  /// client of the old version calls a path the new server does not serve.
  /// The contract itself may still be fine, so these differences are kept
  /// apart from the other ones.
  final List<CompatibilityIssue> pathIssues;

  /// Whether the client works against the server.
  bool get isCompatible => compatibility == Compatibility.compatible;

  /// Whether the client works against the server over the wire.
  ///
  /// The paths have to match too: a client that calls `/v1/users/1` cannot
  /// talk to a server that only serves `/v2/users/1`.
  bool get isDeployable => isCompatible && pathIssues.isEmpty;

  /// The differences that keep the client from working.
  List<CompatibilityIssue> get fatalIssues =>
      issues.where((issue) => issue.isFatal).toList();

  /// A description of the report.
  String describe() {
    if (compatibility == Compatibility.compatible && pathIssues.isEmpty) {
      return 'the client works against the server';
    }

    final buffer = StringBuffer();
    switch (compatibility) {
      case Compatibility.compatible:
        buffer.write('the client works against the server');
      case Compatibility.partial:
        buffer.write('the client works, but the server lacks a part of it');
      case Compatibility.incompatible:
        buffer.write('the client cannot work against the server');
    }

    final all = <CompatibilityIssue>[...issues, ...pathIssues];
    if (all.isNotEmpty) {
      buffer.write(':');
      for (final issue in all) {
        buffer.write('\n  - ${issue.toString()}');
      }
    }
    return buffer.toString();
  }
}

/// Compares the client [client] with the server [server].
///
/// The two contracts are matched by the simple name of their services, of
/// their methods and of their messages, because the package of a contract
/// carries its version: `users.v1` and `users.v2` hold the same service under
/// two package names.
CompatibilityReport analyzeCompatibility(Contract client, Contract server) {
  final issues = <CompatibilityIssue>[];
  final pathIssues = <CompatibilityIssue>[];

  for (final clientService in client.services) {
    final serverService = _serviceOf(server, clientService);
    if (serverService == null) {
      issues.add(
        CompatibilityIssue(
          kind: CompatibilityIssueKind.missingService,
          subject: clientService.name,
          message:
              'the server does not have the service "${clientService.name}"',
        ),
      );
      continue;
    }

    for (final clientMethod in clientService.methods) {
      final subject = '${clientService.name}.${clientMethod.name}';
      final serverMethod = _methodOf(serverService, clientMethod.name);

      if (serverMethod == null) {
        issues.add(
          CompatibilityIssue(
            kind: CompatibilityIssueKind.missingMethod,
            subject: subject,
            message: 'the server does not have the method "$subject"',
          ),
        );
        continue;
      }

      if (_simpleType(clientMethod.requestType) !=
          _simpleType(serverMethod.requestType)) {
        issues.add(
          CompatibilityIssue(
            kind: CompatibilityIssueKind.changedRequestType,
            subject: subject,
            message: 'the request changed from "${clientMethod.requestType}" '
                'to "${serverMethod.requestType}"',
          ),
        );
      }

      if (_simpleType(clientMethod.responseType) !=
          _simpleType(serverMethod.responseType)) {
        issues.add(
          CompatibilityIssue(
            kind: CompatibilityIssueKind.changedResponseType,
            subject: subject,
            message: 'the response changed from "${clientMethod.responseType}" '
                'to "${serverMethod.responseType}"',
          ),
        );
      }

      final clientPaths = _pathsOf(clientMethod);
      final serverPaths = _pathsOf(serverMethod);
      if (!_samePaths(clientPaths, serverPaths)) {
        pathIssues.add(
          CompatibilityIssue(
            kind: CompatibilityIssueKind.changedPath,
            subject: subject,
            message: 'the REST binding changed from [$clientPaths] '
                'to [$serverPaths]',
          ),
        );
      }

      _compareMessage(client, server, clientMethod.requestType, issues);
      _compareMessage(client, server, clientMethod.responseType, issues);
    }
  }

  final hasFatal = issues.any((issue) => issue.isFatal);
  final compatibility = hasFatal
      ? Compatibility.incompatible
      : issues.isEmpty
          ? Compatibility.compatible
          : Compatibility.partial;

  return CompatibilityReport(
    compatibility: compatibility,
    issues: issues,
    pathIssues: pathIssues,
  );
}

/// The compatibility of every pair of versions of a contract.
class CompatibilityMatrix {
  /// Creates a matrix out of [reports].
  ///
  /// The key of [reports] is the pair of the labels of the client and of the
  /// server, joined by a vertical bar.
  CompatibilityMatrix({
    required this.versions,
    required Map<String, CompatibilityReport> reports,
  }) : _reports = reports;

  /// The labels of the versions of the matrix, in the order they were given.
  final List<String> versions;

  final Map<String, CompatibilityReport> _reports;

  /// The report of the client [client] against the server [server].
  CompatibilityReport report(String client, String server) {
    final report = _reports['$client|$server'];
    if (report == null) {
      throw ArgumentError('Unknown pair "$client" and "$server".');
    }
    return report;
  }

  /// The servers the client [client] works against.
  List<String> serversFor(String client) =>
      versions.where((server) => report(client, server).isDeployable).toList();

  /// The clients the server [server] answers to.
  List<String> clientsFor(String server) =>
      versions.where((client) => report(client, server).isDeployable).toList();

  /// Whether every client works against every server of the matrix.
  bool get isFullyCompatible => versions.every(
        (client) =>
            versions.every((server) => report(client, server).isDeployable),
      );

  /// The matrix as a table of text.
  ///
  /// The rows are the clients, the columns are the servers. A cell reads
  /// `yes` when the client works against the server, `partly` when the
  /// server lacks a part of what the client expects and `no` when the client
  /// cannot work against the server at all. A `*` marks a cell whose REST
  /// paths differ, so the wire does not match even though the contract does.
  String table() {
    final marks = <List<String>>[
      for (final client in versions)
        <String>[for (final server in versions) _mark(client, server)],
    ];

    const header = 'client \\ server';
    final labelWidth = versions.fold<int>(
      header.length,
      (longest, version) => version.length > longest ? version.length : longest,
    );
    final cellWidth = marks.expand((row) => row).fold<int>(
        0, (longest, mark) => mark.length > longest ? mark.length : longest);

    final buffer = StringBuffer();
    buffer.writeln(
      '${header.padRight(labelWidth + 2)}'
      '${versions.map((v) => v.padRight(cellWidth + 2)).join()}',
    );

    for (var index = 0; index < versions.length; index++) {
      buffer.writeln(
        '${versions[index].padRight(labelWidth + 2)}'
        '${marks[index].map((mark) => mark.padRight(cellWidth + 2)).join()}',
      );
    }

    buffer.writeln();
    buffer.writeln('* the REST paths of the two versions differ.');

    return buffer.toString();
  }

  /// The mark of the client [client] against the server [server].
  String _mark(String client, String server) {
    final analysis = report(client, server);
    final mark = switch (analysis.compatibility) {
      Compatibility.compatible => 'yes',
      Compatibility.partial => 'partly',
      Compatibility.incompatible => 'no',
    };
    return analysis.pathIssues.isEmpty ? mark : '$mark*';
  }

  /// The matrix as a Markdown table.
  String markdown() {
    final buffer = StringBuffer();
    buffer.writeln('| client \\ server | ${versions.join(' | ')} |');
    buffer.writeln('| --- | ${versions.map((_) => '---').join(' | ')} |');

    for (final client in versions) {
      final cells = versions.map((server) => _mark(client, server)).toList();
      buffer.writeln('| $client | ${cells.join(' | ')} |');
    }

    buffer.writeln();
    buffer.writeln('`*` — the REST paths of the two versions differ.');

    return buffer.toString();
  }

  /// The details of every pair of the matrix.
  String details() {
    final buffer = StringBuffer();
    for (final client in versions) {
      for (final server in versions) {
        final analysis = report(client, server);
        buffer.writeln('$client -> $server: ${analysis.describe()}');
      }
    }
    return buffer.toString();
  }
}

/// Builds the matrix of the versions of a contract.
///
/// The key of [versions] is the label of the version, e.g. `v1`.
CompatibilityMatrix buildCompatibilityMatrix(Map<String, Contract> versions) {
  final reports = <String, CompatibilityReport>{};
  for (final client in versions.keys) {
    for (final server in versions.keys) {
      reports['$client|$server'] = analyzeCompatibility(
        versions[client]!,
        versions[server]!,
      );
    }
  }

  return CompatibilityMatrix(
    versions: versions.keys.toList(),
    reports: reports,
  );
}

/// The service of [contract] that matches [service].
Service? _serviceOf(Contract contract, Service service) {
  for (final candidate in contract.services) {
    if (candidate.fullName == service.fullName) {
      return candidate;
    }
  }
  for (final candidate in contract.services) {
    if (candidate.name == service.name) {
      return candidate;
    }
  }
  return null;
}

/// The method of [service] named [name].
Method? _methodOf(Service service, String name) {
  for (final method in service.methods) {
    if (method.name == name) {
      return method;
    }
  }
  return null;
}

/// The message of [contract] named [type].
Message? _messageOf(Contract contract, String type) {
  final name = _simpleType(type);
  for (final message in contract.messages) {
    if (message.name == name) {
      return message;
    }
  }
  return null;
}

/// Compares the message [type] of the client with the one of the server.
void _compareMessage(
  Contract client,
  Contract server,
  String type,
  List<CompatibilityIssue> issues,
) {
  final clientMessage = _messageOf(client, type);
  if (clientMessage == null) {
    return;
  }

  final serverMessage = _messageOf(server, type);
  if (serverMessage == null) {
    issues.add(
      CompatibilityIssue(
        kind: CompatibilityIssueKind.missingMessage,
        subject: clientMessage.name,
        message: 'the server does not have the message "${clientMessage.name}"',
      ),
    );
    return;
  }

  for (final field in clientMessage.fields) {
    final serverField = serverMessage.field(field.name);
    if (serverField == null) {
      issues.add(
        CompatibilityIssue(
          kind: CompatibilityIssueKind.missingField,
          subject: '${clientMessage.name}.${field.name}',
          message: 'the server does not have the field '
              '"${clientMessage.name}.${field.name}"',
        ),
      );
      continue;
    }

    if (_simpleType(serverField.type) != _simpleType(field.type)) {
      issues.add(
        CompatibilityIssue(
          kind: CompatibilityIssueKind.changedFieldType,
          subject: '${clientMessage.name}.${field.name}',
          message: 'the type of "${clientMessage.name}.${field.name}" changed '
              'from "${field.type}" to "${serverField.type}"',
        ),
      );
    }
    if (serverField.number != field.number) {
      issues.add(
        CompatibilityIssue(
          kind: CompatibilityIssueKind.changedFieldNumber,
          subject: '${clientMessage.name}.${field.name}',
          message:
              'the number of "${clientMessage.name}.${field.name}" changed '
              'from ${field.number} to ${serverField.number}',
        ),
      );
    }
    if (serverField.repeated != field.repeated) {
      issues.add(
        CompatibilityIssue(
          kind: CompatibilityIssueKind.changedFieldLabel,
          subject: '${clientMessage.name}.${field.name}',
          message: 'the label of "${clientMessage.name}.${field.name}" changed',
        ),
      );
    }
  }
}

/// The simple name of a type, without the package it belongs to.
String _simpleType(String type) {
  final separator = type.lastIndexOf('.');
  return separator == -1 ? type : type.substring(separator + 1);
}

/// The REST bindings of a method, as text.
String _pathsOf(Method method) =>
    method.httpRules.map((rule) => '${rule.method} ${rule.path}').join(', ');

/// Whether the two sets of REST bindings are the same.
bool _samePaths(String left, String right) {
  final leftSet = left.split(', ').where((value) => value.isNotEmpty).toSet();
  final rightSet = right.split(', ').where((value) => value.isNotEmpty).toSet();
  return leftSet.length == rightSet.length && leftSet.containsAll(rightSet);
}
