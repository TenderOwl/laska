/// The workspace manifest of a Laska project.
///
/// The manifest is a small YAML file that lists the services of the workspace.
/// `laska dev` starts every service of the manifest, aggregates their logs and
/// points them at the local collector.
///
/// ```yaml
/// services:
///   - name: users
///     entrypoint: services/users/bin/server.dart
///     port: 8080
///     environment:
///       DATABASE_URL: postgres://localhost/users
/// ```
library;

import 'dart:io';

/// A service of the workspace.
class WorkspaceService {
  /// Creates a service.
  const WorkspaceService({
    required this.name,
    required this.entrypoint,
    required this.port,
    this.environment = const <String, String>{},
  });

  /// The name of the service, used as the prefix of its logs.
  final String name;

  /// The Dart file the service runs.
  final String entrypoint;

  /// The port the service listens to.
  final int port;

  /// The environment variables of the service.
  final Map<String, String> environment;
}

/// The workspace of a project.
class Workspace {
  /// Creates a workspace.
  const Workspace(this.services);

  /// The services of the workspace.
  final List<WorkspaceService> services;
}

/// Raised when the manifest of the workspace cannot be read.
class WorkspaceException implements Exception {
  /// Creates an exception with [message].
  WorkspaceException(this.message);

  /// Human readable description of the problem.
  final String message;

  @override
  String toString() => 'WorkspaceException: $message';
}

/// Reads the workspace manifest in [file].
///
/// The manifest holds a `services` list. Every service has a `name`, an
/// `entrypoint` and a `port`, and it may hold an `environment` map.
Workspace readWorkspace(File file) {
  if (!file.existsSync()) {
    throw WorkspaceException('The manifest "${file.path}" does not exist.');
  }
  final services = _parseServices(file.readAsLinesSync());
  if (services.isEmpty) {
    throw WorkspaceException(
      'The manifest "${file.path}" holds no service. A manifest looks like:\n'
      'services:\n'
      '  - name: users\n'
      '    entrypoint: bin/server.dart\n'
      '    port: 8080',
    );
  }
  return Workspace(services);
}

List<WorkspaceService> _parseServices(List<String> lines) {
  final services = <WorkspaceService>[];

  var inServices = false;
  Map<String, String>? fields;
  Map<String, String>? environment;
  var inEnvironment = false;

  void flush() {
    if (fields == null) {
      return;
    }
    final name = fields!['name'];
    final entrypoint = fields!['entrypoint'];
    if (name == null || entrypoint == null) {
      throw WorkspaceException(
        'A service of the manifest needs a name and an entrypoint.',
      );
    }
    services.add(
      WorkspaceService(
        name: name,
        entrypoint: entrypoint,
        port: int.tryParse(fields!['port'] ?? '') ?? 8080,
        environment: environment ?? const <String, String>{},
      ),
    );
    fields = null;
    environment = null;
  }

  for (final raw in lines) {
    final line = raw.replaceAll('\t', '  ');
    final trimmed = line.trim();
    if (trimmed.isEmpty || trimmed.startsWith('#')) {
      continue;
    }
    final indent = line.length - line.trimLeft().length;

    if (!inServices) {
      if (trimmed == 'services:') {
        inServices = true;
      }
      continue;
    }

    if (trimmed.startsWith('- ')) {
      flush();
      inEnvironment = false;
      fields = <String, String>{};
      _assign(fields!, trimmed.substring(2));
      continue;
    }

    if (fields == null) {
      continue;
    }

    if (trimmed == 'environment:') {
      inEnvironment = true;
      continue;
    }

    if (inEnvironment) {
      final separator = trimmed.indexOf(':');
      if (separator == -1) {
        continue;
      }
      environment ??= <String, String>{};
      environment![trimmed.substring(0, separator).trim()] =
          _unquote(trimmed.substring(separator + 1).trim());
      continue;
    }

    if (indent == 0) {
      // A new top level key ends the list of the services.
      inServices = false;
      flush();
      continue;
    }

    _assign(fields!, trimmed);
  }

  flush();
  return services;
}

void _assign(Map<String, String> fields, String text) {
  final separator = text.indexOf(':');
  if (separator == -1) {
    return;
  }
  final key = text.substring(0, separator).trim();
  final value = text.substring(separator + 1).trim();
  if (key.isEmpty) {
    return;
  }
  fields[key] = _unquote(value);
}

String _unquote(String value) {
  if (value.length >= 2 &&
      ((value.startsWith('"') && value.endsWith('"')) ||
          (value.startsWith("'") && value.endsWith("'")))) {
    return value.substring(1, value.length - 1);
  }
  return value;
}
