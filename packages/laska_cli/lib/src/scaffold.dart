/// The scaffolding of a service and of a workspace.
///
/// The scaffolder writes a service that is ready to run: the contract, the
/// generated code, the implementation, the entrypoint, a test and a manifest.
/// Nothing of it has to be written by hand, and everything of it can be
/// changed afterwards — the files are ordinary Dart and an ordinary contract.
library;

import 'dart:io';
import 'dart:isolate';

import 'package:laska_contracts/laska_contracts.dart';

import 'workspace.dart';

/// The directory of the Laska workspace the CLI belongs to.
///
/// Returns `null` when the CLI does not run from a workspace — when it is
/// installed as a published package, for instance.
Future<Directory?> laskaWorkspaceRoot() async {
  final uri = await Isolate.resolvePackageUri(
    Uri.parse('package:laska_core/laska_core.dart'),
  );
  if (uri == null) {
    return null;
  }

  // .../packages/laska_core/lib/laska_core.dart → the root of the workspace.
  var directory = File.fromUri(uri).parent.parent;
  final packages = directory.parent;
  if (!packages.path.endsWith('packages')) {
    return null;
  }
  return packages.parent;
}

/// The result of a scaffolding.
class ScaffoldResult {
  /// Creates a result.
  const ScaffoldResult({required this.written, this.manifest});

  /// The paths of the written files.
  final List<String> written;

  /// The path of the manifest of the workspace, when one was written.
  final String? manifest;
}

/// Raised when a service cannot be scaffolded.
class ScaffoldException implements Exception {
  /// Creates an exception with [message].
  ScaffoldException(this.message);

  /// Human readable description of the problem.
  final String message;

  @override
  String toString() => 'ScaffoldException: $message';
}

/// Scaffolds the service [name] inside [directory].
///
/// The service is written in the directory itself, which is created when it
/// does not exist yet. The [port] is the port the service listens to in
/// development, and the [package] is the package of the contract, which
/// defaults to `<name>.v1`.
///
/// When [localWorkspace] is the directory of a Laska workspace, the project
/// depends on the packages of that workspace instead of the published ones.
Future<ScaffoldResult> scaffoldService(
  String name, {
  required Directory directory,
  int port = 8080,
  String? package,
  String? localWorkspace,
}) async {
  final snake = snakeCase(name);
  if (snake.isEmpty) {
    throw ScaffoldException('The name of a service cannot be empty.');
  }

  final pascal = pascalCase(snake);
  // The records of the service are named after the entity it manages, so a
  // service called "users" manages "users" and answers with a "User".
  final entity = snake.endsWith('s') && snake.length > 1
      ? snake.substring(0, snake.length - 1)
      : snake;
  final entityPascal = pascalCase(entity);
  final contractPackage = package ?? '$snake.v1';
  final serviceName = '${pascal}Service';
  final method = 'Get$entityPascal';
  final requestType = 'Get${entityPascal}Request';
  final responseType = entityPascal;
  final path = '/v1/$snake';
  final generated = '$snake.pb.dart';

  final api = Directory('${directory.path}/api');
  final bin = Directory('${directory.path}/bin');
  final lib = Directory('${directory.path}/lib');
  final test = Directory('${directory.path}/test');
  for (final target in <Directory>[api, bin, lib, test]) {
    await target.create(recursive: true);
  }

  final written = <String>[];

  final contractFile = File('${api.path}/$snake.proto');
  await contractFile.writeAsString(
    _contract(
      package: contractPackage,
      service: serviceName,
      method: method,
      requestType: requestType,
      responseType: responseType,
      path: path,
    ),
  );
  written.add(contractFile.path);

  final generatedFiles = await _generate(
    contractFile,
    directory: Directory('${lib.path}/generated'),
    title: '$pascal API',
  );
  written.addAll(generatedFiles);

  final serviceFile = File('${lib.path}/${snake}_service.dart');
  await serviceFile.writeAsString(
    _service(
      service: serviceName,
      method: camelCase(method),
      requestType: requestType,
      responseType: responseType,
      generated: generated,
    ),
  );
  written.add(serviceFile.path);

  final entrypoint = File('${bin.path}/server.dart');
  await entrypoint.writeAsString(
    _entrypoint(
      name: snake,
      service: serviceName,
      generated: generated,
    ),
  );
  written.add(entrypoint.path);

  final testFile = File('${test.path}/${snake}_service_test.dart');
  await testFile.writeAsString(
    _test(
      name: snake,
      service: serviceName,
      path: path,
      generated: generated,
    ),
  );
  written.add(testFile.path);

  final pubspec = File('${directory.path}/pubspec.yaml');
  await pubspec.writeAsString(
    _pubspec(
      name: '${snake}_service',
      description: 'The $snake service.',
      localWorkspace: localWorkspace,
      directory: directory,
    ),
  );
  written.add(pubspec.path);

  return ScaffoldResult(written: written);
}

/// Scaffolds the workspace [name] in [directory].
///
/// The workspace holds the manifest and the first service, so the command
/// gives a project that runs with `laska dev` right away.
Future<ScaffoldResult> scaffoldWorkspace(
  String name, {
  required Directory directory,
  int port = 8080,
  String? localWorkspace,
}) async {
  final snake = snakeCase(name);
  final root = Directory('${directory.path}/$snake');
  await root.create(recursive: true);

  final service = await scaffoldService(
    snake,
    directory: Directory('${root.path}/services/$snake'),
    port: port,
    localWorkspace: localWorkspace,
  );

  final manifest = File('${root.path}/laska.yaml');
  await manifest.writeAsString(
    renderWorkspace(
      Workspace(
        services: <WorkspaceService>[
          WorkspaceService(
            name: snake,
            entrypoint: 'services/$snake/bin/server.dart',
            port: port,
          ),
        ],
      ),
    ),
  );

  return ScaffoldResult(
    written: <String>[...service.written, manifest.path],
    manifest: manifest.path,
  );
}

/// Compiles the contract of the service and writes the generated code.
Future<List<String>> _generate(
  File contract, {
  required Directory directory,
  required String title,
}) async {
  final compiler = ContractCompiler(title: title);
  final result = compiler.compile(<ProtoSource>[
    ProtoSource(contract.uri.pathSegments.last, contract.readAsStringSync()),
  ]);
  return writeGeneratedFiles(result, directory.path);
}

/// The contract of the scaffolded service.
String _contract({
  required String package,
  required String service,
  required String method,
  required String requestType,
  required String responseType,
  required String path,
}) =>
    '''syntax = "proto3";

package $package;

// $service manages the records of the application.
service $service {
  // The policy of the calls to the service.
  option (laska.policy) = {
    timeout_ms: 2000
    max_attempts: 3
    backoff_ms: 100
    max_backoff_ms: 2000
    jitter: true
  };

  // $method returns a single record by its identifier.
  rpc $method($requestType) returns ($responseType) {
    option (google.api.http) = { get: "$path/{id}" };
    option (laska.policy) = { idempotent: true };
  }
}

// Request of the $method method.
message $requestType {
  // Stable identifier of the record.
  string id = 1;
}

// A record of the application.
message $responseType {
  // Stable identifier of the record.
  string id = 1;

  // Name of the record.
  string name = 2;
}
''';

/// The implementation of the scaffolded service.
String _service({
  required String service,
  required String method,
  required String requestType,
  required String responseType,
  required String generated,
}) =>
    '''import 'package:laska_core/laska_core.dart';

import 'generated/$generated';

/// The implementation of the $service service.
class ${service}Impl implements $service {
  final Map<String, $responseType> _records = <String, $responseType>{};

  @override
  Future<$responseType> $method($requestType request) async {
    final record = _records[request.id];
    if (record == null) {
      throw HttpException(
        404,
        '$responseType "\${request.id}" was not found',
        code: 'not_found',
      );
    }
    return record;
  }
}
''';

/// The entrypoint of the scaffolded service.
String _entrypoint({
  required String name,
  required String service,
  required String generated,
}) =>
    '''import 'package:laska_core/laska_core.dart';

import '../lib/generated/$generated';
import '../lib/${name}_service.dart';

Future<void> main(List<String> arguments) async {
  final app = Laska();

  Observability.install(
    app,
    logger: Logger(service: '$name', version: '0.1.0'),
  );

  register$service(app, ${service}Impl());

  await run(app, arguments: arguments);
}
''';

/// The test of the scaffolded service.
String _test({
  required String name,
  required String service,
  required String path,
  required String generated,
}) =>
    '''import 'package:laska_core/laska_core.dart';
import 'package:laska_test/laska_test.dart';
import 'package:test/test.dart';

import '../lib/generated/$generated';
import '../lib/${name}_service.dart';

void main() {
  test('an unknown record is reported as a problem document', () async {
    final app = Laska();
    register$service(app, ${service}Impl());

    final client = testClient(app);

    final response = await client.get('$path/u_1');
    response.expectStatus(404);
  });
}
''';

/// The manifest of the scaffolded service.
String _pubspec({
  required String name,
  required String description,
  String? localWorkspace,
  Directory? directory,
}) {
  final overrides = <String, String>{};

  if (localWorkspace != null && directory != null) {
    overrides['laska_core'] =
        _pathDependency(localWorkspace, 'laska_core', directory);
    overrides['laska_contracts'] =
        _pathDependency(localWorkspace, 'laska_contracts', directory);
    overrides['laska_test'] =
        _pathDependency(localWorkspace, 'laska_test', directory);
  }

  final buffer = StringBuffer()
    ..writeln('name: $name')
    ..writeln('description: $description')
    ..writeln('version: 0.1.0')
    ..writeln('publish_to: none')
    ..writeln()
    ..writeln('environment:')
    ..writeln('  sdk: ^3.6.0')
    ..writeln()
    ..writeln('dependencies:')
    ..writeln('  http: ^1.6.0')
    ..writeln('  laska_core: ^0.1.0')
    ..writeln()
    ..writeln('dev_dependencies:')
    ..writeln('  laska_contracts: ^0.1.0')
    ..writeln('  laska_test: ^0.1.0')
    ..writeln('  test: ^1.33.0');

  if (overrides.isNotEmpty) {
    buffer.writeln();
    buffer.writeln(
        '# The packages of the local Laska workspace. The override is');
    buffer.writeln('# removed when the project uses the published packages.');
    buffer.writeln('dependency_overrides:');
    overrides.forEach((key, value) {
      buffer.writeln('  $key: $value');
    });
  }

  return buffer.toString();
}

/// The dependency on a package of the local workspace.
String _pathDependency(
  String workspace,
  String package,
  Directory directory,
) {
  final path = relativePath(
    directory.absolute.path,
    '$workspace/packages/$package',
  );
  return '{path: $path}';
}
