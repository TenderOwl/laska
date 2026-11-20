/// The workspace manifest of a Laska project.
///
/// The manifest is a small YAML file that describes the services of the
/// workspace. `laska dev` starts every service of the manifest, aggregates
/// their logs and points them at the local collector.
///
/// ```yaml
/// environment:
///   LOG_LEVEL: debug
///
/// services:
///   - name: users
///     entrypoint: services/users/bin/server.dart
///     port: 8080
///   - name: orders
///     entrypoint: services/orders/bin/server.dart
///     port: 8081
///     depends_on: [users]
///     environment:
///       DATABASE_URL: postgres://localhost/orders
/// ```
library;

import 'dart:async';
import 'dart:io';

import 'yaml.dart';

/// The kind of a service of the workspace.
///
/// The kind tells what the participant of the workspace is: a service of a
/// contract or an application that carries the frontend of the workspace.
enum WorkspaceServiceKind {
  /// A service of a contract.
  ///
  /// It answers over the REST projection of its contract and over gRPC, and
  /// it is called by the other services of the workspace.
  service,

  /// An application that carries the frontend of the workspace.
  ///
  /// It serves the files of the frontend and calls the services behind it, so
  /// the browser of the user talks to the application and not to the services.
  app;

  /// The name of the kind in the manifest, e.g. `app`.
  String get label => name;

  /// The kind of the [name], or `null` when the name is not a kind.
  static WorkspaceServiceKind? byName(String name) {
    for (final kind in WorkspaceServiceKind.values) {
      if (kind.label == name) {
        return kind;
      }
    }
    return null;
  }
}

/// A service of the workspace.
class WorkspaceService {
  /// Creates a service.
  const WorkspaceService({
    required this.name,
    required this.entrypoint,
    required this.port,
    this.kind = WorkspaceServiceKind.service,
    this.environment = const <String, String>{},
    this.dependsOn = const <String>[],
  });

  /// The name of the service, used as the prefix of its logs.
  final String name;

  /// The kind of the service, e.g. an application of the frontend.
  final WorkspaceServiceKind kind;

  /// The Dart file the service runs.
  final String entrypoint;

  /// The port the service listens to.
  final int port;

  /// The environment variables of the service.
  final Map<String, String> environment;

  /// The names of the services this service waits for.
  ///
  /// The services are started in the order of their dependencies, and a
  /// service is only started once the services it depends on answer.
  final List<String> dependsOn;

  /// The environment variable that holds the address of the service.
  String get urlVariable => '${name.toUpperCase().replaceAll('-', '_')}_URL';

  /// The address of the service.
  String url([String host = '127.0.0.1']) => 'http://$host:$port';
}

/// The workspace of a project.
class Workspace {
  /// Creates a workspace.
  const Workspace({
    required this.services,
    this.environment = const <String, String>{},
  });

  /// The services of the workspace.
  final List<WorkspaceService> services;

  /// The environment variables every service of the workspace inherits.
  final Map<String, String> environment;

  /// The service named [name], or `null` when the workspace has no such
  /// service.
  WorkspaceService? service(String name) {
    for (final service in services) {
      if (service.name == name) {
        return service;
      }
    }
    return null;
  }
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
/// `entrypoint` and a `port`, and it may hold an `environment` map and a
/// `depends_on` list. The manifest itself may hold an `environment` map that
/// every service inherits.
Workspace readWorkspace(File file) {
  if (!file.existsSync()) {
    throw WorkspaceException('The manifest "${file.path}" does not exist.');
  }

  final Object? document;
  try {
    document = parseYaml(file.readAsStringSync());
  } on YamlException catch (error) {
    throw WorkspaceException(
      'The manifest "${file.path}" cannot be read: ${error.message}',
    );
  }

  if (document is! Map) {
    throw WorkspaceException(
      'The manifest "${file.path}" holds no service. A manifest looks like:\n'
      'services:\n'
      '  - name: users\n'
      '    entrypoint: bin/server.dart\n'
      '    port: 8080',
    );
  }

  final rawServices = document['services'];
  if (rawServices is! List || rawServices.isEmpty) {
    throw WorkspaceException(
      'The manifest "${file.path}" holds no service. A manifest looks like:\n'
      'services:\n'
      '  - name: users\n'
      '    entrypoint: bin/server.dart\n'
      '    port: 8080',
    );
  }

  final services = <WorkspaceService>[];
  for (final raw in rawServices) {
    if (raw is! Map) {
      throw WorkspaceException(
        'A service of the manifest needs a name and an entrypoint.',
      );
    }
    final name = raw['name'];
    final entrypoint = raw['entrypoint'];
    if (name is! String || entrypoint is! String) {
      throw WorkspaceException(
        'A service of the manifest needs a name and an entrypoint.',
      );
    }
    services.add(
      WorkspaceService(
        name: name,
        entrypoint: entrypoint,
        port: int.tryParse('${raw['port'] ?? ''}') ?? 8080,
        kind: _kindOf(raw['kind'], name),
        environment: _stringMap(raw['environment']),
        dependsOn: _stringList(raw['depends_on']),
      ),
    );
  }

  final workspace = Workspace(
    services: services,
    environment: _stringMap(document['environment']),
  );

  // The dependencies are checked while the manifest is read, so a wrong
  // manifest is reported before anything is started.
  orderServices(workspace.services);

  return workspace;
}

/// Writes the workspace in the YAML of the manifest.
///
/// The manifest is written from the model, so the file is always a manifest
/// the parser can read. The comments of a hand written manifest are lost when
/// it is written again.
String renderWorkspace(Workspace workspace) {
  final buffer = StringBuffer();

  if (workspace.environment.isNotEmpty) {
    buffer.writeln('environment:');
    for (final entry in workspace.environment.entries) {
      buffer.writeln('  ${entry.key}: ${entry.value}');
    }
    buffer.writeln();
  }

  buffer.writeln('services:');
  for (final service in workspace.services) {
    buffer.writeln('  - name: ${service.name}');
    // The kind is written when it is not the default, so the manifest of a
    // workspace of services stays the manifest it was.
    if (service.kind != WorkspaceServiceKind.service) {
      buffer.writeln('    kind: ${service.kind.label}');
    }
    buffer.writeln('    entrypoint: ${service.entrypoint}');
    buffer.writeln('    port: ${service.port}');
    if (service.dependsOn.isNotEmpty) {
      buffer.writeln('    depends_on: [${service.dependsOn.join(', ')}]');
    }
    if (service.environment.isNotEmpty) {
      buffer.writeln('    environment:');
      for (final entry in service.environment.entries) {
        buffer.writeln('      ${entry.key}: ${entry.value}');
      }
    }
  }

  return buffer.toString();
}

/// Adds the [service] to the manifest in [file].
///
/// The manifest is created when it does not exist yet, and it is written again
/// from the model when it does.
Future<void> addServiceToManifest(File file, WorkspaceService service) async {
  var workspace = const Workspace(services: <WorkspaceService>[]);
  if (file.existsSync()) {
    workspace = readWorkspace(file);
    if (workspace.service(service.name) != null) {
      throw WorkspaceException(
        'The manifest "${file.path}" already holds a service called '
        '"${service.name}".',
      );
    }
  }

  await file.parent.create(recursive: true);
  await file.writeAsString(
    renderWorkspace(
      Workspace(
        services: <WorkspaceService>[...workspace.services, service],
        environment: workspace.environment,
      ),
    ),
  );
}

/// The path of the entrypoint of a service, relative to its manifest.
///
/// A manifest holds the paths of the entrypoints relative to its own
/// directory, so a workspace can be started from anywhere.
String resolveEntrypoint(File manifest, String entrypoint) {
  final file = File(entrypoint);
  if (file.isAbsolute) {
    return entrypoint;
  }
  return '${manifest.parent.absolute.path}/$entrypoint';
}

/// The directory the service of the [entrypoint] is started in.
///
/// The directory is the one of the package of the service — the directory that
/// holds its `pubspec.yaml` — so the paths of the service are read against
/// its own package and not against the directory the command was started in.
///
/// The [fallback] is used when the service does not belong to a package.
String? workingDirectoryOf(String entrypoint, {String? fallback}) {
  var directory = File(entrypoint).absolute.parent;

  for (var depth = 0; depth < 8; depth++) {
    if (File('${directory.path}/pubspec.yaml').existsSync()) {
      return directory.path;
    }

    final parent = directory.parent;
    if (parent.path == directory.path) {
      break;
    }
    directory = parent;
  }

  return fallback;
}

/// The path of [target] relative to the directory of [from].
///
/// The path uses the slashes of a manifest, whatever the platform is.
String relativePath(String from, String target) {
  final fromParts = from
      .replaceAll('\\', '/')
      .split('/')
      .where((part) => part.isNotEmpty && part != '.')
      .toList();
  final targetParts = target
      .replaceAll('\\', '/')
      .split('/')
      .where((part) => part.isNotEmpty && part != '.')
      .toList();

  var common = 0;
  while (common < fromParts.length &&
      common < targetParts.length &&
      fromParts[common] == targetParts[common]) {
    common++;
  }

  final up = List<String>.filled(fromParts.length - common, '..');
  final down = targetParts.skip(common);
  return <String>[...up, ...down].join('/');
}

/// Orders the services so that a service comes after the services it depends
/// on.
///
/// The order of the services that do not depend on each other is kept, so the
/// manifest stays the order of the start. Raises a [WorkspaceException] when a
/// service depends on a service that does not exist or when the dependencies
/// form a cycle.
List<WorkspaceService> orderServices(List<WorkspaceService> services) {
  final byName = <String, WorkspaceService>{
    for (final service in services) service.name: service,
  };

  for (final service in services) {
    for (final dependency in service.dependsOn) {
      if (!byName.containsKey(dependency)) {
        throw WorkspaceException(
          'The service "${service.name}" depends on "$dependency", which is '
          'not a service of the manifest.',
        );
      }
      if (dependency == service.name) {
        throw WorkspaceException(
          'The service "${service.name}" depends on itself.',
        );
      }
    }
  }

  final ordered = <WorkspaceService>[];
  final done = <String>{};
  final visiting = <String>{};

  void visit(WorkspaceService service) {
    if (done.contains(service.name)) {
      return;
    }
    if (!visiting.add(service.name)) {
      throw WorkspaceException(
        'The dependencies of the services form a cycle around '
        '"${service.name}".',
      );
    }
    for (final dependency in service.dependsOn) {
      visit(byName[dependency]!);
    }
    visiting.remove(service.name);
    done.add(service.name);
    ordered.add(service);
  }

  for (final service in services) {
    visit(service);
  }

  return ordered;
}

/// The environment of a service of the workspace.
///
/// The variables of the workspace come first, the variables of the service
/// come last, and every service of the workspace is reachable through the
/// `<NAME>_URL` variable, which is what the service discovery of the runtime
/// reads.
Map<String, String> serviceEnvironment(
  WorkspaceService service,
  Workspace workspace,
) {
  final environment = <String, String>{
    ...workspace.environment,
    ...service.environment,
  };

  for (final other in workspace.services) {
    environment[other.urlVariable] = other.url();
  }

  return environment;
}

/// Waits until the port [port] of [host] accepts a connection.
///
/// Returns `true` when the port is open and `false` when the wait ran out.
Future<bool> waitForPort(
  String host,
  int port, {
  Duration timeout = const Duration(seconds: 30),
  Duration interval = const Duration(milliseconds: 100),
}) async {
  final deadline = DateTime.now().add(timeout);

  while (DateTime.now().isBefore(deadline)) {
    try {
      final socket = await Socket.connect(host, port, timeout: interval);
      socket.destroy();
      return true;
    } on SocketException {
      await Future<void>.delayed(interval);
    } on TimeoutException {
      await Future<void>.delayed(interval);
    }
  }

  return false;
}

/// The kind of the service [name].
///
/// A service without a kind is a service of a contract. A kind the runtime
/// does not know is refused, so a manifest does not hold a participant that
/// nobody knows how to start.
WorkspaceServiceKind _kindOf(Object? value, String name) {
  if (value == null) {
    return WorkspaceServiceKind.service;
  }
  final kind = WorkspaceServiceKind.byName('$value');
  if (kind == null) {
    throw WorkspaceException(
      'The service "$name" has the kind "$value", which is not a kind the '
      'runtime knows. The kinds are: '
      '${WorkspaceServiceKind.values.map((kind) => kind.label).join(', ')}.',
    );
  }
  return kind;
}

/// The variables of a map of the manifest.
Map<String, String> _stringMap(Object? value) {
  if (value is! Map) {
    return const <String, String>{};
  }
  return <String, String>{
    for (final entry in value.entries) '${entry.key}': '${entry.value}',
  };
}

/// The values of a list of the manifest.
List<String> _stringList(Object? value) {
  if (value is! List) {
    return const <String>[];
  }
  return <String>[for (final item in value) '$item'];
}
