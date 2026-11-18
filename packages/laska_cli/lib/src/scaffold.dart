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

/// The service that a scaffolded service calls.
///
/// The service behind the dependency holds the records, and the scaffolded
/// service answers with a view of them. The client of the dependency comes
/// from the contract of the dependency, so it carries the policy of the
/// calls: the timeout, the retries, the circuit breaker and the bulkhead.
class ServiceDependency {
  /// Creates a dependency.
  const ServiceDependency({
    required this.name,
    required this.package,
    required this.generated,
    required this.service,
    required this.method,
    required this.requestType,
    required this.responseType,
    required this.entity,
  });

  /// The name of the service, e.g. `shop`.
  final String name;

  /// The package of the service, e.g. `shop_service`.
  final String package;

  /// The generated file of the contract of the service, e.g. `shop.pb.dart`.
  final String generated;

  /// The interface of the service, e.g. `ShopService`.
  final String service;

  /// The method the scaffolded service calls, e.g. `GetShop`.
  final String method;

  /// The request of the method, e.g. `GetShopRequest`.
  final String requestType;

  /// The answer of the method, e.g. `Shop`.
  final String responseType;

  /// The name of the records of the service, e.g. `shop`.
  final String entity;
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
///
/// When the service calls the service of the [dependency], the implementation
/// answers with a view of the records of that service.
Future<ScaffoldResult> scaffoldService(
  String name, {
  required Directory directory,
  int port = 8080,
  String? package,
  String? localWorkspace,
  ServiceDependency? dependency,
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
  // A service that calls another service answers with a view of the records
  // of that service, so the names of the two do not clash in the code that
  // uses both of them.
  final recordEntity =
      dependency == null ? entity : '${dependency.entity}_view';
  final entityPascal = pascalCase(recordEntity);
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
    dependency == null
        ? _service(
            service: serviceName,
            method: camelCase(method),
            requestType: requestType,
            responseType: responseType,
            generated: generated,
          )
        : _serviceWithDependency(
            service: serviceName,
            method: camelCase(method),
            requestType: requestType,
            responseType: responseType,
            generated: generated,
            dependency: dependency,
          ),
  );
  written.add(serviceFile.path);

  final entrypoint = File('${bin.path}/server.dart');
  await entrypoint.writeAsString(
    dependency == null
        ? _entrypoint(
            name: snake,
            service: serviceName,
            generated: generated,
          )
        : _entrypointWithDependency(
            name: snake,
            service: serviceName,
            generated: generated,
            dependency: dependency,
          ),
  );
  written.add(entrypoint.path);

  final testFile = File('${test.path}/${snake}_service_test.dart');
  await testFile.writeAsString(
    dependency == null
        ? _test(
            name: snake,
            service: serviceName,
            path: path,
            generated: generated,
          )
        : _testWithDependency(
            name: snake,
            service: serviceName,
            path: path,
            generated: generated,
            dependency: dependency,
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
      dependency: dependency,
      dependencyDirectory: dependency == null
          ? null
          : Directory('${directory.parent.path}/${dependency.name}'),
    ),
  );
  written.add(pubspec.path);

  return ScaffoldResult(written: written);
}

/// Scaffolds the workspace [name] in [directory].
///
/// The workspace holds two services and the manifest that ties them together:
/// the first service keeps the records, the second one calls it through the
/// client of its contract and answers with a view of the records. The two
/// services carry the tracing, the policy of the calls and their own tests, so
/// the command gives a project that runs with `laska dev` right away and
/// shows the whole path of the framework.
Future<ScaffoldResult> scaffoldWorkspace(
  String name, {
  required Directory directory,
  int port = 8080,
  String? localWorkspace,
}) async {
  final snake = snakeCase(name);
  final root = Directory('${directory.path}/$snake');
  await root.create(recursive: true);

  final gateway = '${snake}_gateway';

  final service = await scaffoldService(
    snake,
    directory: Directory('${root.path}/services/$snake'),
    port: port,
    localWorkspace: localWorkspace,
  );

  final second = await scaffoldService(
    gateway,
    directory: Directory('${root.path}/services/$gateway'),
    port: port + 1,
    localWorkspace: localWorkspace,
    dependency: ServiceDependency(
      name: snake,
      package: '${snake}_service',
      generated: '$snake.pb.dart',
      service: '${pascalCase(snake)}Service',
      method: 'Get${pascalCase(_singular(snake))}',
      requestType: 'Get${pascalCase(_singular(snake))}Request',
      responseType: pascalCase(_singular(snake)),
      entity: _singular(snake),
    ),
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
          WorkspaceService(
            name: gateway,
            entrypoint: 'services/$gateway/bin/server.dart',
            port: port + 1,
            dependsOn: <String>[snake],
          ),
        ],
      ),
    ),
  );

  return ScaffoldResult(
    written: <String>[...service.written, ...second.written, manifest.path],
    manifest: manifest.path,
  );
}

/// The singular of the name [snake].
String _singular(String snake) => snake.endsWith('s') && snake.length > 1
    ? snake.substring(0, snake.length - 1)
    : snake;

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
  final Map<String, $responseType> _records = <String, $responseType>{
    // One record, so the service answers something on the first call. Replace
    // the map with the table of your database.
    'u_1': $responseType(id: 'u_1', name: 'A record'),
  };

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

/// The implementation of the scaffolded service that calls another service.
///
/// The client of the dependency comes from the contract of the dependency, so
/// it carries the policy of the calls: the timeout, the retries, the circuit
/// breaker and the bulkhead.
String _serviceWithDependency({
  required String service,
  required String method,
  required String requestType,
  required String responseType,
  required String generated,
  required ServiceDependency dependency,
}) =>
    '''import 'package:laska_core/laska_core.dart';
import 'package:${dependency.package}/generated/${dependency.generated}';

import 'generated/$generated';

/// The implementation of the $service service.
class ${service}Impl implements $service {
  ${service}Impl({required this.${dependency.name}});

  /// The client of the service that keeps the records.
  final ${dependency.service}Client ${dependency.name};

  @override
  Future<$responseType> $method($requestType request) async {
    final record;
    try {
      record = await ${dependency.name}.${camelCase(dependency.method)}(
        ${dependency.requestType}(id: request.id),
      );
    } on LaskaApiException catch (error) {
      // The status of the service behind becomes the status of this service,
      // so the caller sees what really happened.
      throw HttpException(
        error.statusCode,
        error.statusCode == 404
            ? 'The record "\${request.id}" was not found'
            : 'The service behind is not available',
        code: error.statusCode == 404 ? 'not_found' : 'dependency_error',
      );
    }
    return $responseType(id: record.id, name: record.name);
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

  await Observability.install(
    app,
    logger: Logger(service: '$name', version: '0.1.0'),
  );

  register$service(app, ${service}Impl());

  await run(app, arguments: arguments);
}
''';

/// The entrypoint of the scaffolded service that calls another service.
String _entrypointWithDependency({
  required String name,
  required String service,
  required String generated,
  required ServiceDependency dependency,
}) =>
    '''import 'dart:io';

import 'package:laska_core/laska_core.dart';
import 'package:${dependency.package}/generated/${dependency.generated}';

import '../lib/generated/$generated';
import '../lib/${name}_service.dart';

Future<void> main(List<String> arguments) async {
  final app = Laska();

  final observability = await Observability.install(
    app,
    logger: Logger(service: '$name', version: '0.1.0'),
  );

  // The address of the service that keeps the records. `laska dev` gives it
  // to every service of the workspace.
  final baseUrl = Platform.environment['${dependency.name.toUpperCase()}_URL'] ??
      'http://127.0.0.1:8080';

  register$service(
    app,
    ${service}Impl(
      ${dependency.name}: ${dependency.service}Client(
        baseUrl: baseUrl,
        // The tracer of the service joins the trace of the caller, so the two
        // services answer with one trace.
        tracer: observability.tracer,
      ),
    ),
  );

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
  test('the service answers with the record it keeps', () async {
    final app = Laska();
    register$service(app, ${service}Impl());

    final client = testClient(app);

    final response = await client.get('$path/u_1');
    response.expectStatus(200);
  });

  test('an unknown record is reported as a problem document', () async {
    final app = Laska();
    register$service(app, ${service}Impl());

    final client = testClient(app);

    final response = await client.get('$path/missing');
    response.expectStatus(404);
  });
}
''';

/// The test of the scaffolded service that calls another service.
///
/// The transport of the test answers the call of the dependency, so the test
/// exercises the whole path without opening a socket.
String _testWithDependency({
  required String name,
  required String service,
  required String path,
  required String generated,
  required ServiceDependency dependency,
}) =>
    '''import 'package:laska_core/laska_core.dart';
import 'package:laska_test/laska_test.dart';
import 'package:${dependency.package}/generated/${dependency.generated}';
import 'package:test/test.dart';

import '../lib/generated/$generated';
import '../lib/${name}_service.dart';

void main() {
  test('the service answers with the record of the service behind it',
      () async {
    final transport = TestTransport();
    transport.enqueueResponse(
      200,
      body: <String, Object?>{'id': 'u_1', 'name': 'A record'},
    );

    final tracer = TestTracer();
    final app = Laska();
    await Observability.install(app, tracer: tracer);
    register$service(
      app,
      ${service}Impl(
        ${dependency.name}: ${dependency.service}Client(
          baseUrl: 'http://localhost:8080',
          transport: transport,
          tracer: tracer,
        ),
      ),
    );

    final client = testClient(app);

    final response = await client.get('$path/u_1');
    response.expectStatus(200);

    final body = response.json as Map<String, dynamic>;
    expect(body['id'], 'u_1');
    expect(body['name'], 'A record');
  });

  test('the call to the service behind belongs to the trace of the request',
      () async {
    final transport = TestTransport();
    transport.enqueueResponse(
      200,
      body: <String, Object?>{'id': 'u_1', 'name': 'A record'},
    );

    final tracer = TestTracer();
    final app = Laska();
    await Observability.install(app, tracer: tracer);
    register$service(
      app,
      ${service}Impl(
        ${dependency.name}: ${dependency.service}Client(
          baseUrl: 'http://localhost:8080',
          transport: transport,
          tracer: tracer,
        ),
      ),
    );

    final client = testClient(app);
    await client.get('$path/u_1');

    // The call to the service behind carries the trace of the request, so the
    // two services answer with one trace.
    expect(transport.requests.first.headers['traceparent'], isNotNull);
  });

  test('the status of the service behind becomes the status of this service',
      () async {
    final transport = TestTransport();
    transport.enqueueResponse(404, body: <String, Object?>{'code': 'not_found'});

    final tracer = TestTracer();
    final app = Laska();
    await Observability.install(app, tracer: tracer);
    register$service(
      app,
      ${service}Impl(
        ${dependency.name}: ${dependency.service}Client(
          baseUrl: 'http://localhost:8080',
          transport: transport,
          tracer: tracer,
        ),
      ),
    );

    final client = testClient(app);

    final response = await client.get('$path/missing');
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
  ServiceDependency? dependency,
  Directory? dependencyDirectory,
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

  final dependencies = <String, String>{
    'http': '^1.6.0',
    'laska_core': '^0.1.0',
  };

  // The client of the service behind comes from the package of that service,
  // so the service depends on it.
  if (dependency != null && dependencyDirectory != null && directory != null) {
    dependencies[dependency.package] =
        '{path: ${relativePath(directory.absolute.path, dependencyDirectory.absolute.path)}}';
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
    ..writeln('dependencies:');
  dependencies.forEach((key, value) {
    buffer.writeln('  $key: $value');
  });
  buffer
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
