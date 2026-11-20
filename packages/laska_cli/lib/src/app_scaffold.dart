/// The scaffolding of an app — the participant of a workspace that carries the
/// frontend.
///
/// The app serves the files of the frontend and calls the services behind it,
/// so the browser of the user talks to the app and not to the services. The
/// calls go through the generated clients of the contracts of those services,
/// and the headers of the caller travel with them.
library;

import 'dart:io';

import 'package:laska_contracts/laska_contracts.dart';

import 'scaffold.dart';
import 'workspace.dart';

/// The method of the service the app calls.
class AppMethod {
  /// Creates a method.
  const AppMethod({
    required this.name,
    required this.requestType,
    required this.responseType,
    this.path,
    this.verb = 'GET',
  });

  /// The name of the method in Dart, e.g. `getUser`.
  final String name;

  /// The type of the request of the method, e.g. `GetUserRequest`.
  final String requestType;

  /// The type of the answer of the method, e.g. `User`.
  final String responseType;

  /// The path of the HTTP binding of the method, e.g. `/v1/users/{id}`.
  ///
  /// The value is `null` when the method has no HTTP binding, so the method
  /// is reachable over gRPC only.
  final String? path;

  /// The HTTP method of the binding, e.g. `GET`.
  final String verb;

  /// The path of the call with the parameters of the path filled in.
  ///
  /// The value is `null` when the method has no HTTP binding.
  String? get samplePath => path?.replaceAll(RegExp(r'\{[^}]+\}'), 'u_1');
}

/// The service of a contract the app calls.
class AppDependency {
  /// Creates a dependency.
  const AppDependency({
    required this.name,
    required this.package,
    required this.generated,
    required this.service,
    required this.methods,
  });

  /// The name of the service in the workspace, e.g. `users`.
  final String name;

  /// The package of the service, e.g. `users_service`.
  final String package;

  /// The path of the generated code inside the package, e.g.
  /// `generated/users.pb.dart`.
  final String generated;

  /// The interface of the service, e.g. `UsersService`.
  final String service;

  /// The methods of the service.
  final List<AppMethod> methods;

  /// The name of the client of the service, e.g. `UsersServiceClient`.
  String get client => '${service}Client';

  /// The name of the proxy of the service, e.g. `UsersProxy`.
  String get proxy => '${_withoutService(service)}Proxy';

  /// The name of the service without the `Service` at its end.
  static String _withoutService(String service) =>
      service.endsWith('Service') && service.length > 'Service'.length
          ? service.substring(0, service.length - 'Service'.length)
          : service;
}

/// Reads the service [service] of the workspace of [root] as a dependency of
/// an app.
///
/// The service is read from the files of its directory: the pubspec holds the
/// name of its package, the contract holds its service and its methods, and
/// the generated code holds the file the app imports.
///
/// Raises a [ScaffoldException] when the service cannot be read.
AppDependency readAppDependency(WorkspaceService service, Directory root) {
  final directory = _directoryOf(service, root);

  final package = _packageOf(directory);
  if (package == null) {
    throw ScaffoldException(
      'The service "${service.name}" has no pubspec, so the app cannot depend '
      'on it.',
    );
  }

  final generated = _generatedOf(directory);
  if (generated == null) {
    throw ScaffoldException(
      'The service "${service.name}" has no generated code, so the app cannot '
      'call it. Run "laska contract compile" in the directory of the service.',
    );
  }

  final contract = _contractOf(directory);
  if (contract == null) {
    throw ScaffoldException(
      'The service "${service.name}" has no contract, so the app cannot call '
      'it.',
    );
  }

  final services = _servicesOf(contract);
  if (services.isEmpty) {
    throw ScaffoldException(
      'The contract of the service "${service.name}" holds no service, so the '
      'app cannot call it.',
    );
  }

  return AppDependency(
    name: service.name,
    package: package,
    generated: generated,
    service: services.first.name,
    methods: <AppMethod>[
      for (final method in services.first.methods)
        AppMethod(
          name: camelCase(method.name),
          requestType: _simpleName(method.requestType),
          responseType: _simpleName(method.responseType),
          path: method.httpRules.isEmpty ? null : method.httpRules.first.path,
          verb:
              method.httpRules.isEmpty ? 'POST' : method.httpRules.first.method,
        ),
    ],
  );
}

/// Scaffolds the app [name] inside [directory].
///
/// The app serves the frontend of the workspace and calls the [dependencies]
/// behind it. The files are written in the directory itself, which is created
/// when it does not exist yet.
///
/// When [localWorkspace] is the directory of a Laska workspace, the project
/// depends on the packages of that workspace instead of the published ones.
Future<ScaffoldResult> scaffoldApp(
  String name, {
  required Directory directory,
  int port = 8080,
  String? localWorkspace,
  List<AppDependency> dependencies = const <AppDependency>[],
}) async {
  final snake = snakeCase(name);
  if (snake.isEmpty) {
    throw ScaffoldException('The name of an app cannot be empty.');
  }

  final bin = Directory('${directory.path}/bin');
  final lib = Directory('${directory.path}/lib');
  final test = Directory('${directory.path}/test');
  final web = Directory('${directory.path}/web');
  for (final target in <Directory>[bin, lib, test, web]) {
    await target.create(recursive: true);
  }

  final written = <String>[];

  final appFile = File('${lib.path}/app.dart');
  await appFile.writeAsString(_app(dependencies: dependencies));
  written.add(appFile.path);

  final entrypoint = File('${bin.path}/server.dart');
  await entrypoint.writeAsString(
    _entrypoint(name: snake, package: '${snake}_app'),
  );
  written.add(entrypoint.path);

  final page = File('${web.path}/index.html');
  await page.writeAsString(_page(name: snake));
  written.add(page.path);

  final script = File('${web.path}/app.js');
  await script.writeAsString(_script(dependencies: dependencies));
  written.add(script.path);

  final testFile = File('${test.path}/app_test.dart');
  await testFile.writeAsString(
    _test(name: snake, package: '${snake}_app', dependencies: dependencies),
  );
  written.add(testFile.path);

  final pubspec = File('${directory.path}/pubspec.yaml');
  await pubspec.writeAsString(
    _pubspec(
      name: '${snake}_app',
      description: 'The $snake app of the workspace.',
      localWorkspace: localWorkspace,
      directory: directory,
      dependencies: dependencies,
      dependencyDirectories: <Directory>[
        for (final dependency in dependencies)
          Directory('${directory.parent.path}/${dependency.name}'),
      ],
    ),
  );
  written.add(pubspec.path);

  return ScaffoldResult(written: written);
}

/// The directory of the service, relative to the root of the workspace.
///
/// The entrypoint of a service is `<directory>/bin/<file>.dart`, so the
/// directory of the service is the entrypoint without its last two parts.
Directory _directoryOf(WorkspaceService service, Directory root) {
  final parts = service.entrypoint
      .replaceAll('\\', '/')
      .split('/')
      .where((part) => part.isNotEmpty && part != '.')
      .toList();
  if (parts.length < 3) {
    return root;
  }
  return Directory(
    '${root.path}/${parts.take(parts.length - 2).join('/')}',
  );
}

/// The name of the package of the service in [directory].
String? _packageOf(Directory directory) {
  final pubspec = File('${directory.path}/pubspec.yaml');
  if (!pubspec.existsSync()) {
    return null;
  }
  for (final line in pubspec.readAsLinesSync()) {
    if (line.startsWith('name:')) {
      return line.substring('name:'.length).trim();
    }
  }
  return null;
}

/// The path of the generated code of the service in [directory].
String? _generatedOf(Directory directory) {
  final generated = Directory('${directory.path}/lib/generated');
  if (!generated.existsSync()) {
    return null;
  }
  final files = generated
      .listSync()
      .whereType<File>()
      .where((file) => file.path.endsWith('.pb.dart'))
      .toList()
    ..sort((left, right) => left.path.compareTo(right.path));
  if (files.isEmpty) {
    return null;
  }
  return 'generated/${files.first.uri.pathSegments.last}';
}

/// The contract of the service in [directory].
String? _contractOf(Directory directory) {
  final api = Directory('${directory.path}/api');
  if (!api.existsSync()) {
    return null;
  }
  final files = api
      .listSync()
      .whereType<File>()
      .where((file) => file.path.endsWith('.proto'))
      .toList()
    ..sort((left, right) => left.path.compareTo(right.path));
  if (files.isEmpty) {
    return null;
  }
  return files.first.readAsStringSync();
}

/// The services of the contract in [source].
List<Service> _servicesOf(String source) {
  final compiler = ContractCompiler();
  final result = compiler.compile(<ProtoSource>[
    ProtoSource('contract.proto', source),
  ]);
  final services = <Service>[];
  for (final file in result.contract.files) {
    services.addAll(file.services);
  }
  return services;
}

/// The first method of the [methods] that has an HTTP binding.
AppMethod? _firstWithPath(List<AppMethod> methods) {
  for (final method in methods) {
    if (method.samplePath != null) {
      return method;
    }
  }
  return null;
}

/// The name of the type without the package in front of it.
String _simpleName(String type) {
  final dot = type.lastIndexOf('.');
  return dot == -1 ? type : type.substring(dot + 1);
}

/// The code of the app.
String _app({required List<AppDependency> dependencies}) {
  final buffer = StringBuffer()
    ..writeln("import 'dart:async';")
    ..writeln("import 'dart:io';")
    ..writeln()
    ..writeln("import 'package:laska_core/laska_core.dart';");
  for (final dependency in dependencies) {
    buffer.writeln(
      "import 'package:${dependency.package}/${dependency.generated}';",
    );
  }
  buffer
    ..writeln()
    ..writeln("/// The key of the zone that holds the request of the caller.")
    ..writeln("const Object _caller = 'laska.app.caller';")
    ..writeln()
    ..writeln('/// Registers the routes of the app.')
    ..writeln('///')
    ..writeln('/// The app serves the frontend of the workspace and calls the')
    ..writeln(
        '/// services behind it, so the browser of the user talks to the app')
    ..writeln('/// and not to the services.')
    ..writeln('///')
    ..writeln(
        '/// The clients of the services may be given, so a test answers the')
    ..writeln('/// calls of the app without opening a socket.');
  final parameters = dependencies.isEmpty
      ? ''
      : ', {${dependencies.map((dependency) => '${dependency.client}? ${camelCase(dependency.name)}').join(', ')}}';
  buffer
    ..writeln('void registerApp(Laska app$parameters) {')
    ..writeln(
        '  // The request of the caller is kept in the zone of the call, so')
    ..writeln(
        '  // the proxy of a service can pass the headers of the caller with')
    ..writeln('  // the call.')
    ..writeln('  app.use(_keepTheCaller());')
    ..writeln()
    ..writeln('  // The frontend of the workspace. The build of the frontend')
    ..writeln('  // belongs to the application: put the result of it in the')
    ..writeln('  // directory of the files.')
    ..writeln(
        "  final files = Platform.environment['LASKA_WEB_ROOT'] ?? 'web';")
    ..writeln("  app.staticFiles('/', files, fallback: 'index.html');");

  for (final dependency in dependencies) {
    final url = '${dependency.name.toUpperCase().replaceAll('-', '_')}_URL';
    final variable = '${camelCase(dependency.name)}Client';
    buffer
      ..writeln()
      ..writeln('  // The service "${dependency.name}" behind the app.')
      ..writeln('  final $variable = ${camelCase(dependency.name)} ??')
      ..writeln('      ${dependency.client}(')
      ..writeln("        baseUrl: Platform.environment['$url'] ??")
      ..writeln("            'http://127.0.0.1:8080',")
      ..writeln('      );')
      ..writeln(
        '  register${dependency.service}(app, ${dependency.proxy}($variable), '
        'grpc: false);',
      );
  }

  buffer.writeln('}');

  for (final dependency in dependencies) {
    buffer
      ..writeln()
      ..writeln('/// The proxy of the "${dependency.name}" service.')
      ..writeln('///')
      ..writeln(
          '/// The proxy forwards the call of the frontend to the service')
      ..writeln(
          '/// behind it and passes the headers of the caller with it, so the')
      ..writeln('/// token of the session of the browser reaches the service.')
      ..writeln('class ${dependency.proxy} implements ${dependency.service} {')
      ..writeln('  /// Creates the proxy of the service behind.')
      ..writeln('  ${dependency.proxy}(this._client);')
      ..writeln()
      ..writeln('  /// The client of the service behind.')
      ..writeln('  final ${dependency.client} _client;');
    for (final method in dependency.methods) {
      buffer
        ..writeln()
        ..writeln('  @override')
        ..writeln(
          '  Future<${method.responseType}> ${method.name}'
          '(${method.requestType} request) =>',
        )
        ..writeln(
          '      _client.${method.name}(request, headers: _headersOfTheCaller());',
        );
    }
    buffer.writeln('}');
  }

  buffer
    ..writeln()
    ..writeln('/// The headers of the caller, e.g. the token of the session.')
    ..writeln('Map<String, String> _headersOfTheCaller() {')
    ..writeln('  final request = Zone.current[_caller];')
    ..writeln('  if (request is! Request) {')
    ..writeln('    return const <String, String>{};')
    ..writeln('  }')
    ..writeln("  final token = request.header('authorization');")
    ..writeln('  if (token == null) {')
    ..writeln('    return const <String, String>{};')
    ..writeln('  }')
    ..writeln("  return <String, String>{'authorization': token};")
    ..writeln('}')
    ..writeln()
    ..writeln('/// The middleware that keeps the request of the caller.')
    ..writeln('Middleware _keepTheCaller() => (request, next) {')
    ..writeln('      return runZoned(')
    ..writeln('        () => next(),')
    ..writeln('        zoneValues: <Object, Object?>{_caller: request},')
    ..writeln('      );')
    ..writeln('    };');

  return buffer.toString();
}

/// The entrypoint of the app.
String _entrypoint({required String name, required String package}) =>
    '''import 'package:laska_core/laska_core.dart';
import 'package:$package/app.dart';

Future<void> main(List<String> arguments) async {
  final app = Laska();

  await Observability.install(
    app,
    logger: Logger(service: '$name', version: '$projectVersion'),
  );

  registerApp(app);

  await run(app, arguments: arguments);
}
''';

/// The page of the frontend of the app.
String _page({required String name}) => '''<!doctype html>
<html lang="en">
  <head>
    <meta charset="utf-8" />
    <meta name="viewport" content="width=device-width, initial-scale=1" />
    <title>$name</title>
    <link rel="stylesheet" href="/app.css" />
  </head>
  <body>
    <main>
      <h1>$name</h1>
      <p id="message">
        The app of the workspace. Replace the files of this directory with the
        build of your frontend.
      </p>
    </main>
    <script src="/app.js"></script>
  </body>
</html>
''';

/// The script of the frontend of the app.
String _script({required List<AppDependency> dependencies}) {
  final buffer = StringBuffer()
    ..writeln('// The frontend of the workspace.')
    ..writeln('//')
    ..writeln(
        '// The build of the frontend belongs to the application: put the')
    ..writeln('// result of it in the directory of the files.');
  if (dependencies.isEmpty) {
    buffer
      ..writeln()
      ..writeln('const message = document.getElementById("message");')
      ..writeln('if (message) {')
      ..writeln('  message.textContent = "The app serves the frontend.";')
      ..writeln('}');
    return buffer.toString();
  }

  buffer
    ..writeln()
    ..writeln('async function main() {')
    ..writeln(
        '  // The app calls the services behind it, so the frontend talks to')
    ..writeln(
        '  // the app and not to the services. The token of the session of')
    ..writeln('  // the browser travels with the call.')
    ..writeln('  const token = sessionStorage.getItem("token") ?? "";');
  for (final dependency in dependencies) {
    final method = _firstWithPath(dependency.methods);
    if (method == null) {
      continue;
    }
    buffer
      ..writeln('  const ${camelCase(dependency.name)} = await fetch(')
      ..writeln('    "${method.samplePath}",')
      ..writeln('    { headers: { authorization: token } },')
      ..writeln('  );');
  }
  buffer.writeln('  return Promise.all([');
  for (final dependency in dependencies) {
    buffer.writeln(
      '    ${camelCase(dependency.name)}.then((response) => response.json()),',
    );
  }
  buffer
    ..writeln('  ]);')
    ..writeln('}')
    ..writeln()
    ..writeln('main().catch((error) => console.error(error));');

  return buffer.toString();
}

/// The test of the app.
String _test({
  required String name,
  required String package,
  required List<AppDependency> dependencies,
}) {
  final buffer = StringBuffer()
    ..writeln("import 'package:laska_core/laska_core.dart';")
    ..writeln("import 'package:laska_test/laska_test.dart';")
    ..writeln("import 'package:test/test.dart';");
  for (final dependency in dependencies) {
    buffer.writeln(
      "import 'package:${dependency.package}/${dependency.generated}';",
    );
  }
  buffer
    ..writeln()
    ..writeln("import 'package:$package/app.dart';")
    ..writeln()
    ..writeln('void main() {')
    ..writeln("  test('the app serves the frontend', () async {")
    ..writeln('    final app = Laska();')
    ..writeln('    registerApp(app);')
    ..writeln()
    ..writeln('    final client = testClient(app);')
    ..writeln()
    ..writeln("    final response = await client.get('/');")
    ..writeln('    response.expectStatus(200);')
    ..writeln('  });');

  for (final dependency in dependencies) {
    final method = _firstWithPath(dependency.methods);
    if (method == null) {
      continue;
    }
    buffer
      ..writeln()
      ..writeln(
        "  test('the app forwards the call to the ${dependency.name} service', "
        '() async {',
      )
      ..writeln('    final transport = TestTransport();')
      ..writeln(
          '    transport.enqueueResponse(200, body: <String, Object?>{});')
      ..writeln()
      ..writeln('    final app = Laska();')
      ..writeln('    registerApp(')
      ..writeln('      app,')
      ..writeln('      ${camelCase(dependency.name)}: ${dependency.client}(')
      ..writeln("        baseUrl: 'http://localhost:8080',")
      ..writeln('        transport: transport,')
      ..writeln('      ),')
      ..writeln('    );')
      ..writeln()
      ..writeln('    final client = testClient(app);')
      ..writeln()
      ..writeln('    await client.get(')
      ..writeln("      '${method.samplePath}',")
      ..writeln('      headers: <String, String>{')
      ..writeln("        'authorization': 'Bearer the-token',")
      ..writeln('      },')
      ..writeln('    );')
      ..writeln()
      ..writeln('    // The call reached the service behind the app, and the')
      ..writeln('    // headers of the caller travelled with it.')
      ..writeln('    expect(transport.requests, hasLength(1));')
      ..writeln(
        "    expect(transport.requests.first.headers['authorization'], "
        "'Bearer the-token');",
      )
      ..writeln('  });');
  }

  buffer
    ..writeln('}')
    ..writeln();

  return buffer.toString();
}

/// The manifest of the app.
String _pubspec({
  required String name,
  required String description,
  String? localWorkspace,
  Directory? directory,
  List<AppDependency> dependencies = const <AppDependency>[],
  List<Directory> dependencyDirectories = const <Directory>[],
}) {
  final overrides = <String, String>{};

  if (localWorkspace != null && directory != null) {
    overrides['laska_core'] =
        pathDependency(localWorkspace, 'laska_core', directory);
    overrides['laska_contracts'] =
        pathDependency(localWorkspace, 'laska_contracts', directory);
    overrides['laska_test'] =
        pathDependency(localWorkspace, 'laska_test', directory);
  }

  final packages = <String, String>{
    'http': '^1.6.0',
    'laska_core': '^${frameworkVersion()}',
  };

  // The client of the service behind comes from the package of that service,
  // so the app depends on it.
  for (var index = 0; index < dependencies.length; index++) {
    final dependency = dependencies[index];
    final dependencyDirectory = dependencyDirectories[index];
    if (directory == null) {
      continue;
    }
    packages[dependency.package] =
        '{path: ${relativePath(directory.absolute.path, dependencyDirectory.absolute.path)}}';
  }

  final buffer = StringBuffer()
    ..writeln('name: $name')
    ..writeln('description: $description')
    ..writeln('version: $projectVersion')
    ..writeln('publish_to: none')
    ..writeln()
    ..writeln('environment:')
    ..writeln('  sdk: ^3.6.0')
    ..writeln()
    ..writeln('dependencies:');
  packages.forEach((key, value) {
    buffer.writeln('  $key: $value');
  });
  buffer
    ..writeln()
    ..writeln('dev_dependencies:')
    ..writeln('  laska_contracts: ^${frameworkVersion()}')
    ..writeln('  laska_test: ^${frameworkVersion()}')
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
