import 'dart:async';
import 'dart:io';

import 'package:args/args.dart';
import 'package:laska_cli/src/ci.dart';
import 'package:laska_cli/src/collector.dart';
import 'package:laska_cli/src/deploy.dart';
import 'package:laska_cli/src/help.dart';
import 'package:laska_cli/src/keys.dart';
import 'package:laska_cli/src/parser.dart';
import 'package:laska_cli/src/scaffold.dart';
import 'package:laska_cli/src/sdk.dart';
import 'package:laska_cli/src/upgrade.dart';
import 'package:laska_cli/src/workspace.dart';
import 'package:laska_core/laska_core.dart';
import 'package:laska_contracts/laska_contracts.dart';

/// Runs the command line interface with [arguments].
///
/// The output is written to [out] and [err], and the exit code of the command
/// is returned. The entry point of the executable only forwards the result to
/// the process, so the commands can also be driven from a test.
///
/// The [environment] holds the variables the processes of the command inherit
/// on top of the environment of the CLI itself.
Future<int> runCli(
  List<String> arguments, {
  StringSink? out,
  StringSink? err,
  Map<String, String>? environment,
}) =>
    _Cli(out: out, err: err, environment: environment).run(arguments);

/// The state of one run of the command line interface.
class _Cli {
  _Cli({StringSink? out, StringSink? err, Map<String, String>? environment})
      : out = out ?? stdout,
        err = err ?? stderr,
        environment = environment ?? const <String, String>{};

  /// The sink the output of the commands is written to.
  final StringSink out;

  /// The sink the errors of the commands are written to.
  final StringSink err;

  /// The variables the processes of the command inherit.
  final Map<String, String> environment;

  /// The exit code of the run.
  int code = 0;

  /// Runs the command of [arguments].
  Future<int> run(List<String> arguments) async {
    final parser = buildParser();
    final help = LaskaHelp(parser: parser, version: cliVersion);

    final ArgResults results;
    try {
      results = parser.parse(arguments);
    } on FormatException catch (error) {
      err.writeln(error.message);
      out.write(help.root());
      code = 64;
      return code;
    }

    if (results.flag('version')) {
      out.writeln('laska $cliVersion');
      return code;
    }

    if (results.flag('help')) {
      out.write(help.root());
      return code;
    }

    final command = results.command;
    if (command == null) {
      if (results.rest.isNotEmpty) {
        err.writeln('Unknown command "${results.rest.join(' ')}".');
        out.write(help.root());
        code = 64;
        return code;
      }
      out.write(help.root());
      return code;
    }

    if (command.name == 'help') {
      return _help(command, help);
    }

    if (command.flag('help')) {
      out.write(help.command(<String>[command.name!])!);
      return code;
    }

    switch (command.name) {
      case 'contract':
        await _runContract(command, help);
      case 'ci:recipe':
        await _ciRecipe(command);
      case 'serve':
        await _serve(command);
      case 'route:list':
        await _routeList(command);
      case 'migrate:run':
        await _migrate(command);
      case 'dev':
        await _dev(command);
      case 'new':
        await _new(command, help);
      case 'deploy:dockerfile':
        await _dockerfile(command);
      case 'deploy:k8s':
        await _kubernetes(command);
      case 'keys':
        await _keys(command, help);
      case 'upgrade':
        await _upgrade(command, help);
      default:
        out.write(help.root());
        code = 64;
    }
    return code;
  }

  /// Prints the help of the CLI or of the command of the path.
  int _help(ArgResults command, LaskaHelp help) {
    final path = command.rest;
    if (path.isEmpty) {
      out.write(help.root());
      return code;
    }

    final text = help.command(path);
    if (text == null) {
      err.writeln('Unknown command "${path.join(' ')}".');
      out.write(help.root());
      code = 64;
      return code;
    }

    out.write(text);
    return code;
  }

  Future<void> _runContract(ArgResults command, LaskaHelp help) async {
    final subcommand = command.command;
    if (subcommand == null) {
      if (command.rest.isNotEmpty) {
        err.writeln('Unknown subcommand "${command.rest.join(' ')}".');
      } else {
        err.writeln('Missing subcommand for "contract".');
      }
      out.write(help.command(<String>['contract'])!);
      code = 64;
      return;
    }

    if (subcommand.flag('help')) {
      out.write(help.command(<String>['contract', subcommand.name!])!);
      return;
    }

    switch (subcommand.name) {
      case 'compile':
        await _compile(subcommand);
      case 'diff':
        await _diff(subcommand);
      case 'lint':
        await _lint(subcommand);
      case 'matrix':
        await _matrix(subcommand);
      default:
        err.writeln('Unknown subcommand "${subcommand.name}".');
        code = 64;
    }
  }

  /// Writes the matrix of the versions of a contract.
  ///
  /// The matrix tells which client of which version works against which
  /// server of which version, so a release does not break a consumer that
  /// still runs.
  Future<void> _matrix(ArgResults options) async {
    final directories = <String, String>{};

    for (final directory in options.multiOption('version')) {
      directories[_labelOf(directory)] = directory;
    }

    final root = options.option('dir');
    if (root != null) {
      final directory = Directory(root);
      if (!directory.existsSync()) {
        err.writeln('The directory "$root" does not exist.');
        code = 66;
        return;
      }
      final children = directory.listSync().whereType<Directory>().toList()
        ..sort((left, right) =>
            _labelOf(left.path).compareTo(_labelOf(right.path)));
      for (final child in children) {
        directories.putIfAbsent(_labelOf(child.path), () => child.path);
      }
    }

    if (directories.length < 2) {
      err.writeln(
        'The matrix needs at least two versions of the contract. Pass '
        '--version for each of them, or --dir for a directory holding one '
        'directory per version.',
      );
      code = 64;
      return;
    }

    final versions = <String, Contract>{};
    for (final entry in directories.entries) {
      try {
        versions[entry.key] = await _loadContract(entry.value);
      } on StateError catch (error) {
        err.writeln(error.message);
        code = 66;
        return;
      }
    }

    final matrix = buildCompatibilityMatrix(versions);

    out.write(matrix.table());

    if (options.flag('details')) {
      out.writeln();
      out.write(matrix.details());
    }

    final output = options.option('out');
    if (output != null) {
      final file = File(output);
      await file.parent.create(recursive: true);
      await file.writeAsString(matrix.markdown());
      out.writeln('written: ${file.path}');
    }
  }

  /// The label of a version of a contract, taken from its directory.
  String _labelOf(String path) {
    final normalized = path.replaceAll('\\', '/');
    final separator = normalized.lastIndexOf('/');
    if (separator == -1) {
      return normalized;
    }
    return normalized.substring(separator + 1);
  }

  /// Checks the contract against the rules of the framework.
  Future<void> _lint(ArgResults options) async {
    final directory = options.option('proto')!;
    final sources = await readProtoDirectory(directory);
    if (sources.isEmpty) {
      err.writeln('No .proto files found in "$directory".');
      code = 66;
      return;
    }

    final problems = lintContract(
      Contract(
        sources
            .map(
              (source) => ProtoParser(
                source.content,
                fileName: source.path,
              ).parse(),
            )
            .toList(),
      ),
    );

    if (problems.isEmpty) {
      out.writeln('No problem found in ${sources.length} file(s).');
      return;
    }

    for (final problem in problems) {
      out.writeln(problem.toString());
    }
    out.writeln();
    out.writeln('${problems.length} problem(s) found.');

    code = 1;
  }

  /// Writes the recipe of the continuous integration.
  Future<void> _ciRecipe(ArgResults options) async {
    final file = File(options.option('out')!);
    await file.parent.create(recursive: true);
    await file.writeAsString(
      renderCiRecipe(
        proto: options.option('proto')!,
        base: options.option('base'),
        candidate: options.option('candidate'),
        matrix: options.option('matrix'),
      ),
    );

    out.writeln('generated: ${file.path}');
  }

  Future<void> _compile(ArgResults options) async {
    final protoDirectory = options.option('proto')!;
    final outputDirectory = options.option('out')!;

    final sources = await readProtoDirectory(protoDirectory);
    if (sources.isEmpty) {
      err.writeln('No .proto files found in "$protoDirectory".');
      code = 66;
      return;
    }

    final compiler = ContractCompiler(
      title: options.option('title')!,
      version: options.option('version')!,
      // The generated code is written for the version of the SDK the package
      // declares, so `dart format` of that package agrees with the code the
      // generator writes.
      languageVersion: sdkVersionOf(outputDirectory),
    );

    final CompileResult result;
    try {
      result = compiler.compile(sources);
    } on ContractCompileException catch (error) {
      err.writeln(error.toString());
      code = 65;
      return;
    }

    for (final warning in result.warnings) {
      out.writeln('warning: $warning');
    }

    final written = await writeGeneratedFiles(result, outputDirectory);
    for (final path in written) {
      out.writeln('generated: $path');
    }
    out.writeln(
      '${result.files.length} Dart file(s) and openapi.json written to '
      '"$outputDirectory".',
    );
  }

  Future<void> _diff(ArgResults options) async {
    final baseDirectory = options.option('base');
    final candidateDirectory = options.option('candidate');
    if (baseDirectory == null || candidateDirectory == null) {
      err.writeln('Both --base and --candidate are required.');
      code = 64;
      return;
    }

    final base = await _loadContract(baseDirectory);
    final candidate = await _loadContract(candidateDirectory);

    final diff = diffContracts(base, candidate);
    final quiet = options.flag('quiet');
    final changes = quiet ? diff.breakingChanges : diff.changes;

    if (changes.isEmpty) {
      out.writeln('No changes detected.');
      return;
    }

    for (final change in changes) {
      out.writeln(change.toString());
    }
    out.writeln();
    out.writeln(
      '${diff.breakingChanges.length} breaking change(s), '
      '${diff.changes.length - diff.breakingChanges.length} non-breaking '
      'change(s).',
    );

    final problem = _versionProblem(base, candidate, diff);
    if (problem != null) {
      err.writeln();
      err.writeln(problem);
      code = 1;
    }

    if (diff.hasBreakingChanges) {
      code = 1;
    }
  }

  /// The problem with the version of the API of the candidate, if any.
  ///
  /// The policy of the versions says: a breaking change goes to the next
  /// major version of the API, and a change that breaks nobody stays in the
  /// version it is in.
  String? _versionProblem(
    Contract base,
    Contract candidate,
    ContractDiff diff,
  ) {
    final baseVersion = apiVersionOf(base);
    final candidateVersion = apiVersionOf(candidate);
    if (baseVersion == null || candidateVersion == null) {
      return null;
    }
    if (baseVersion.name != candidateVersion.name) {
      return null;
    }

    final required =
        diff.hasBreakingChanges ? baseVersion.nextMajor : baseVersion;
    if (candidateVersion.major == required.major) {
      return null;
    }

    if (diff.hasBreakingChanges) {
      return 'The contract has breaking changes, so the version of the API '
          'must go from ${baseVersion.package} to ${required.package}, '
          'but the candidate is ${candidateVersion.package}.';
    }

    return 'The contract has no breaking changes, so the version of the API '
        'must stay ${baseVersion.package}, '
        'but the candidate is ${candidateVersion.package}.';
  }

  Future<void> _serve(ArgResults options) async {
    final entrypoint = _resolveEntrypoint(options.option('entrypoint'));
    if (entrypoint == null) {
      return;
    }

    final supervisor = Supervisor(
      SupervisorOptions(
        entrypoint: entrypoint,
        executable: Platform.resolvedExecutable,
        workers: int.tryParse(options.option('workers') ?? ''),
        address: options.option('address')!,
        port: int.tryParse(options.option('port') ?? '') ?? 3789,
        environment: environment,
        logger: Logger(service: 'laska'),
      ),
    );

    await supervisor.run();
  }

  Future<void> _routeList(ArgResults options) async {
    final entrypoint = _resolveEntrypoint(options.option('entrypoint'));
    if (entrypoint == null) {
      return;
    }

    final result = await Process.run(
      Platform.resolvedExecutable,
      <String>[entrypoint, routeListFlag],
      environment: <String, String>{
        ...Platform.environment,
        ...environment,
      },
    );
    out.write(result.stdout);
    if (result.exitCode != 0) {
      err.write(result.stderr);
      code = result.exitCode;
    }
  }

  Future<void> _migrate(ArgResults options) async {
    final entrypoint = _resolveEntrypoint(options.option('entrypoint'));
    if (entrypoint == null) {
      return;
    }

    final result = await Process.run(
      Platform.resolvedExecutable,
      <String>[entrypoint, migrateFlag],
      environment: <String, String>{
        ...Platform.environment,
        ...environment,
        'LASKA_MIGRATIONS_DIRECTORY': options.option('directory')!,
      },
    );
    out.write(result.stdout);
    if (result.exitCode != 0) {
      err.write(result.stderr);
      code = result.exitCode;
    }
  }

  /// Writes the Dockerfile of every service of the workspace.
  Future<void> _dockerfile(ArgResults options) async {
    final workspace = _readManifest(options.option('manifest')!);
    if (workspace == null) {
      return;
    }

    final written = await writeDockerfiles(
      workspace,
      output: options.option('out')!,
      image: options.option('image')!,
    );

    for (final path in written) {
      out.writeln('generated: $path');
    }
  }

  /// Writes the Kubernetes manifests of every service of the workspace.
  Future<void> _kubernetes(ArgResults options) async {
    final workspace = _readManifest(options.option('manifest')!);
    if (workspace == null) {
      return;
    }

    final written = await writeKubernetesManifests(
      workspace,
      output: options.option('out')!,
      image: options.option('image')!,
      namespace: options.option('namespace')!,
    );

    for (final path in written) {
      out.writeln('generated: $path');
    }
  }

  /// Generates a key of the service.
  ///
  /// The private key is written to a file of its own, and the key set of the
  /// service is written next to it, so the service may publish the key set
  /// and keep the private key to itself.
  Future<void> _keys(ArgResults command, LaskaHelp help) async {
    final subcommand = command.command;
    if (subcommand == null) {
      if (command.rest.isNotEmpty) {
        err.writeln('Unknown subcommand "${command.rest.join(' ')}".');
      } else {
        err.writeln('Missing subcommand for "keys".');
      }
      out.write(help.command(<String>['keys'])!);
      code = 64;
      return;
    }

    if (subcommand.flag('help')) {
      out.write(help.command(<String>['keys', subcommand.name!])!);
      return;
    }

    if (subcommand.name != 'generate') {
      err.writeln('Unknown subcommand "${subcommand.name}".');
      code = 64;
      return;
    }

    final name = subcommand.option('alg')!;
    final algorithm = keyAlgorithmOf(name);
    if (algorithm == null) {
      err.writeln(
        'The algorithm "$name" is not supported. Use one of rs256, rs384, '
        'rs512, es256, es384, es512 or hs256.',
      );
      code = 64;
      return;
    }

    final bits = int.tryParse(subcommand.option('bits') ?? '') ?? 2048;
    if (bits < 1024) {
      err.writeln('The size of the key of RSA must be at least 1024 bits.');
      code = 64;
      return;
    }

    final KeyGeneration result;
    try {
      result = generateKey(
        directory: subcommand.option('out')!,
        algorithm: algorithm,
        kid: subcommand.option('kid'),
        bits: bits,
      );
    } on KeyGenerationException catch (error) {
      err.writeln(error.message);
      code = 65;
      return;
    }

    out.writeln('generated: ${result.privateKeyFile}');
    out.writeln('generated: ${result.jwksFile}');
    out.writeln();
    out.writeln('Keep the private key to yourself and publish the key set.');
  }

  /// Moves the version of the API of the service.
  ///
  /// The version of the API lives in the name of the package of the contract
  /// and in the paths of the REST projection, so the contract, the generated
  /// code and the calls of the service follow the new version together.
  Future<void> _upgrade(ArgResults options, LaskaHelp help) async {
    final api = options.option('api');
    final from = options.option('from');
    final to = options.option('to');

    if (from == null || to == null) {
      err.writeln('The options --from and --to are required.');
      out.write(help.command(<String>['upgrade'])!);
      code = 64;
      return;
    }

    if (api == null) {
      await _upgradeFramework(options, from, to);
      return;
    }

    if (from == to) {
      err.writeln('The version of the API does not change.');
      code = 64;
      return;
    }

    final dryRun = options.flag('dry-run');
    final result = await applyCodemods(
      Directory(options.option('path')!),
      <Codemod>[apiVersionCodemod(api: api, from: from, to: to)],
      dryRun: dryRun,
    );

    for (final path in result.changedFiles) {
      out.writeln('${dryRun ? 'would change' : 'changed'}: $path');
    }
    out.writeln();
    out.writeln(
      '${result.changedFiles.length} file(s) '
      '${dryRun ? 'would change' : 'changed'}.',
    );

    if (dryRun && result.changedFiles.isNotEmpty) {
      out.writeln('Nothing was written. Run the command without --dry-run.');
    }
  }

  /// Moves the service to the version [to] of the framework.
  Future<void> _upgradeFramework(
    ArgResults options,
    String from,
    String to,
  ) async {
    final codemods = frameworkCodemodsBetween(from, to);
    if (codemods.isEmpty) {
      out.writeln('No codemod is needed to go from $from to $to.');
      return;
    }

    final dryRun = options.flag('dry-run');
    final result = await applyCodemods(
      Directory(options.option('path')!),
      codemods,
      dryRun: dryRun,
    );

    for (final path in result.changedFiles) {
      out.writeln('${dryRun ? 'would change' : 'changed'}: $path');
    }
    out.writeln();
    out.writeln(
      '${result.changedFiles.length} file(s) '
      '${dryRun ? 'would change' : 'changed'}.',
    );
  }

  /// Reads the manifest of the workspace.
  ///
  /// Reports the problem and returns `null` when the manifest cannot be read.
  Workspace? _readManifest(String path) {
    final file = File(path);
    if (!file.existsSync()) {
      err.writeln('The manifest "$path" does not exist.');
      code = 66;
      return null;
    }

    try {
      return readWorkspace(file);
    } on WorkspaceException catch (error) {
      err.writeln(error.message);
      code = 65;
      return null;
    }
  }

  /// Scaffolds a service or a workspace.
  ///
  /// `laska new service <name>` writes a service in the current directory and
  /// adds it to the manifest of the workspace. `laska new <name>` writes a
  /// whole workspace with a first service in it.
  Future<void> _new(ArgResults command, LaskaHelp help) async {
    final arguments = command.rest;
    if (arguments.isEmpty) {
      err.writeln('Missing the name of the project.');
      out.write(help.command(<String>['new'])!);
      code = 64;
      return;
    }

    final isService = arguments.first == 'service';
    final name = isService
        ? (arguments.length > 1 ? arguments[1] : '')
        : arguments.first;

    if (name.isEmpty) {
      err.writeln('Missing the name of the service.');
      out.write(help.command(<String>['new'])!);
      code = 64;
      return;
    }

    final output = command.option('out')!;
    final port = int.tryParse(command.option('port') ?? '') ?? 8080;

    String? localWorkspace;
    if (command.flag('local')) {
      final root = await laskaWorkspaceRoot();
      if (root == null) {
        err.writeln(
          'The local Laska workspace was not found, so the project depends on '
          'the published packages.',
        );
      } else {
        localWorkspace = root.path;
      }
    }

    try {
      if (isService) {
        final snake = snakeCase(name);
        final directory = Directory('$output/$snake');
        final result = await scaffoldService(
          name,
          directory: directory,
          port: port,
          localWorkspace: localWorkspace,
        );

        final manifest = File(command.option('manifest')!);
        await addServiceToManifest(
          manifest,
          WorkspaceService(
            name: snake,
            entrypoint: relativePath(
              manifest.parent.absolute.path,
              '${directory.absolute.path}/bin/server.dart',
            ),
            port: port,
          ),
        );

        for (final path in result.written) {
          out.writeln('created: $path');
        }
        out.writeln('created: ${manifest.path}');
        out.writeln();
        out.writeln('Run it with: laska dev');
        return;
      }

      final result = await scaffoldWorkspace(
        name,
        directory: Directory(output),
        port: port,
        localWorkspace: localWorkspace,
      );

      for (final path in result.written) {
        out.writeln('created: $path');
      }
      out.writeln();
      out.writeln('Run it with: cd ${snakeCase(name)} && laska dev');
    } on ScaffoldException catch (error) {
      err.writeln(error.message);
      code = 65;
    } on WorkspaceException catch (error) {
      err.writeln(error.message);
      code = 65;
    } on ContractCompileException catch (error) {
      err.writeln(error.toString());
      code = 65;
    }
  }

  /// Runs the workspace in development.
  ///
  /// Every service of the manifest is started, the logs of the services are
  /// aggregated in one stream and the telemetry of the services is sent to the
  /// local collector, which prints the traces it receives.
  ///
  /// The services are started in the order of their dependencies: a service
  /// waits for the services it depends on to answer before it is started.
  Future<void> _dev(ArgResults options) async {
    final manifest = File(options.option('manifest')!);

    if (manifest.existsSync()) {
      try {
        final parsed = readWorkspace(manifest);
        return await _devWorkspace(
          parsed,
          options,
          manifest: manifest,
          startupTimeout: Duration(
            seconds:
                int.tryParse(options.option('startup-timeout') ?? '') ?? 30,
          ),
        );
      } on WorkspaceException catch (error) {
        err.writeln(error.message);
        code = 65;
        return;
      }
    }

    final entrypoint = _resolveEntrypoint(options.option('entrypoint'));
    if (entrypoint == null) {
      return;
    }

    await _devWorkspace(
      Workspace(
        services: <WorkspaceService>[
          WorkspaceService(
            name: 'app',
            entrypoint: entrypoint,
            port: int.tryParse(options.option('port') ?? '') ?? 3789,
          ),
        ],
      ),
      options,
      startupTimeout: Duration(
        seconds: int.tryParse(options.option('startup-timeout') ?? '') ?? 30,
      ),
    );
  }

  /// Starts every service of the [workspace] and waits for the end.
  Future<void> _devWorkspace(
    Workspace workspace,
    ArgResults options, {
    File? manifest,
    Duration startupTimeout = const Duration(seconds: 30),
  }) async {
    final services = orderServices(workspace.services);

    // The paths of the manifest are relative to the manifest itself, so a
    // workspace can be started from any directory.
    final entrypoints = <String, String>{};
    for (final service in services) {
      final entrypoint = manifest == null
          ? service.entrypoint
          : resolveEntrypoint(manifest, service.entrypoint);
      entrypoints[service.name] = entrypoint;

      // The entrypoints are checked before anything is started, so a wrong
      // manifest costs nothing.
      if (!File(entrypoint).existsSync()) {
        err.writeln(
          'The entrypoint "$entrypoint" of the service '
          '"${service.name}" does not exist.',
        );
        code = 66;
        return;
      }
    }

    LocalCollector? collector;
    if (!options.flag('no-collector')) {
      collector = LocalCollector();
      try {
        await collector.start(
          port: int.tryParse(options.option('collector-port') ?? '') ?? 4318,
        );
      } on SocketException catch (error) {
        err.writeln('The collector could not start: ${error.message}');
        code = 69;
        return;
      }
      out.writeln('=> collector on ${collector.endpoint}');
    }

    final supervisors = <Supervisor>[];
    try {
      for (final service in services) {
        for (final dependency in service.dependsOn) {
          final target = workspace.service(dependency);
          if (target == null) {
            continue;
          }
          final ready = await waitForPort(
            '127.0.0.1',
            target.port,
            timeout: startupTimeout,
          );
          if (!ready) {
            err.writeln(
              'The service "$dependency" did not answer on the port '
              '${target.port} in ${startupTimeout.inSeconds}s, so '
              '"${service.name}" was not started.',
            );
            code = 69;
            return;
          }
        }

        final entrypoint = File(entrypoints[service.name]!);

        if (!options.flag('no-pub-get')) {
          final problem = await _resolveDependencies(entrypoint.path);
          if (problem != null) {
            err.writeln(
              'The dependencies of the service "${service.name}" could not be '
              'resolved:',
            );
            err.writeln(problem);
            code = 69;
            return;
          }
        }

        out.writeln(
          '=> ${service.name} on http://127.0.0.1:${service.port}',
        );

        final supervisor = Supervisor(
          SupervisorOptions(
            entrypoint: entrypoint.absolute.path,
            executable: Platform.resolvedExecutable,
            address: '127.0.0.1',
            port: service.port,
            label: service.name,
            environment: <String, String>{
              ...Platform.environment,
              ...environment,
              ...serviceEnvironment(service, workspace),
              'OTEL_SERVICE_NAME': service.name,
              if (collector != null) ...<String, String>{
                'OTEL_EXPORTER_OTLP_ENDPOINT': collector.endpoint.toString(),
                'OTEL_EXPORTER_OTLP_PROTOCOL': 'http/json',
              },
            },
            logger: Logger(service: 'laska'),
          ),
        );
        supervisors.add(supervisor);
        unawaited(supervisor.run());
      }

      out.writeln(
        '=> ${services.length} service(s) started. Press Ctrl+C to stop.',
      );

      await Completer<void>().future;
    } finally {
      // The collector holds the event loop of the process, so it is closed when
      // the command returns.
      await collector?.stop();
    }
  }

  /// Resolves the dependencies of the service of the [entrypoint].
  ///
  /// The package of the service is the first directory above the entrypoint
  /// that holds a `pubspec.yaml`. Returns the error of the command when the
  /// dependencies could not be resolved, and `null` when they are.
  Future<String?> _resolveDependencies(String entrypoint) async {
    var directory = File(entrypoint).parent;

    for (var depth = 0; depth < 4; depth++) {
      if (File('${directory.path}/pubspec.yaml').existsSync()) {
        final result = await Process.run(
          Platform.resolvedExecutable,
          <String>['pub', 'get'],
          workingDirectory: directory.path,
        );
        if (result.exitCode != 0) {
          return result.stderr.toString().trim();
        }
        return null;
      }

      final parent = directory.parent;
      if (parent.path == directory.path) {
        break;
      }
      directory = parent;
    }

    return null;
  }

  /// Resolves the entrypoint of the service.
  ///
  /// Returns `null` and reports the problem when no entrypoint can be found.
  String? _resolveEntrypoint(String? option) {
    if (option != null) {
      final file = File(option);
      if (!file.existsSync()) {
        err.writeln('The entrypoint "$option" does not exist.');
        code = 66;
        return null;
      }
      return file.absolute.path;
    }

    for (final candidate in const <String>[
      'bin/server.dart',
      'bin/main.dart'
    ]) {
      final file = File(candidate);
      if (file.existsSync()) {
        return file.absolute.path;
      }
    }

    err.writeln(
      'No entrypoint found. Pass --entrypoint with the Dart file of the service.',
    );
    code = 66;
    return null;
  }
}

Future<Contract> _loadContract(String directory) async {
  final sources = await readProtoDirectory(directory);
  if (sources.isEmpty) {
    throw StateError('No .proto files found in "$directory".');
  }
  return Contract(
    sources
        .map(
          (source) => ProtoParser(
            source.content,
            fileName: source.path,
          ).parse(),
        )
        .toList(),
  );
}
