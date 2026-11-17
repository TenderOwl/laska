import 'dart:async';
import 'dart:io';

import 'package:args/args.dart';
import 'package:laska_cli/src/collector.dart';
import 'package:laska_cli/src/workspace.dart';
import 'package:laska_core/laska_core.dart';
import 'package:laska_contracts/laska_contracts.dart';

/// The version of the CLI.
const String cliVersion = '0.1.0';

/// Entry point of the `laska` command line interface.
Future<void> main(List<String> arguments) async {
  final commands = _buildParser();
  final parser = commands.parser;

  final ArgResults results;
  try {
    results = parser.parse(arguments);
  } on FormatException catch (error) {
    stderr.writeln(error.message);
    stderr.writeln(parser.usage);
    exitCode = 64;
    return;
  }

  if (results.flag('version')) {
    stdout.writeln('laska $cliVersion');
    return;
  }

  final command = results.command;
  if (command == null) {
    stdout.writeln(parser.usage);
    return;
  }

  switch (command.name) {
    case 'contract':
      await _runContract(command, commands);
    case 'serve':
      await _serve(command);
    case 'route:list':
      await _routeList(command);
    case 'migrate:run':
      await _migrate(command);
    case 'dev':
      await _dev(command);
    default:
      stdout.writeln(parser.usage);
      exitCode = 64;
  }
}

({ArgParser parser, ArgParser contract, ArgParser compile, ArgParser diff})
    _buildParser() {
  final parser = ArgParser()
    ..addFlag(
      'version',
      negatable: false,
      help: 'Print the version of the CLI.',
    );

  final contract = parser.addCommand('contract');

  final compile = contract.addCommand('compile')
    ..addOption(
      'proto',
      help: 'Directory containing the .proto files.',
      defaultsTo: 'proto',
    )
    ..addOption(
      'out',
      help: 'Directory the generated code is written to.',
      defaultsTo: 'lib/generated',
    )
    ..addOption(
      'title',
      help: 'Title of the generated OpenAPI document.',
      defaultsTo: 'Laska API',
    )
    ..addOption(
      'version',
      help: 'Version of the generated OpenAPI document.',
      defaultsTo: '0.1.0',
    );

  final diff = contract.addCommand('diff')
    ..addOption(
      'base',
      help: 'Directory containing the baseline .proto files.',
    )
    ..addOption(
      'candidate',
      help: 'Directory containing the candidate .proto files.',
    )
    ..addFlag(
      'quiet',
      negatable: false,
      help: 'Only report breaking changes.',
    );

  parser.addCommand('serve')
    ..addOption(
      'entrypoint',
      help: 'Dart file of the service. Defaults to bin/server.dart.',
    )
    ..addOption(
      'workers',
      help: 'Number of worker processes. Defaults to the number of cores.',
    )
    ..addOption(
      'port',
      help: 'Port the workers bind to.',
      defaultsTo: '3789',
    )
    ..addOption(
      'address',
      help: 'Address the workers bind to.',
      defaultsTo: '0.0.0.0',
    );

  parser.addCommand('route:list').addOption(
        'entrypoint',
        help: 'Dart file of the service. Defaults to bin/server.dart.',
      );

  parser.addCommand('migrate:run')
    ..addOption(
      'entrypoint',
      help: 'Dart file of the service. Defaults to bin/server.dart.',
    )
    ..addOption(
      'directory',
      help: 'Directory holding the migration files.',
      defaultsTo: 'migrations',
    );

  parser.addCommand('dev')
    ..addOption(
      'manifest',
      help: 'Workspace manifest. Defaults to laska.yaml.',
      defaultsTo: 'laska.yaml',
    )
    ..addOption(
      'entrypoint',
      help: 'Dart file of a single service, when there is no manifest.',
    )
    ..addOption(
      'port',
      help: 'Port of the service, when there is no manifest.',
      defaultsTo: '3789',
    )
    ..addOption(
      'collector-port',
      help: 'Port of the local telemetry collector.',
      defaultsTo: '4318',
    )
    ..addFlag(
      'no-collector',
      negatable: false,
      help: 'Do not start the local telemetry collector.',
    );

  return (parser: parser, contract: contract, compile: compile, diff: diff);
}

Future<void> _runContract(
  ArgResults command,
  ({
    ArgParser parser,
    ArgParser contract,
    ArgParser compile,
    ArgParser diff,
  }) commands,
) async {
  final subcommand = command.command;
  if (subcommand == null) {
    stderr.writeln('Missing subcommand for "contract".');
    stderr.writeln(commands.compile.usage);
    stderr.writeln(commands.diff.usage);
    exitCode = 64;
    return;
  }

  switch (subcommand.name) {
    case 'compile':
      await _compile(subcommand);
    case 'diff':
      await _diff(subcommand);
    default:
      stderr.writeln('Unknown subcommand "${subcommand.name}".');
      exitCode = 64;
  }
}

Future<void> _compile(ArgResults options) async {
  final protoDirectory = options.option('proto')!;
  final outputDirectory = options.option('out')!;

  final sources = await readProtoDirectory(protoDirectory);
  if (sources.isEmpty) {
    stderr.writeln('No .proto files found in "$protoDirectory".');
    exitCode = 66;
    return;
  }

  final compiler = ContractCompiler(
    title: options.option('title')!,
    version: options.option('version')!,
  );

  final CompileResult result;
  try {
    result = compiler.compile(sources);
  } on ContractCompileException catch (error) {
    stderr.writeln(error.toString());
    exitCode = 65;
    return;
  }

  for (final warning in result.warnings) {
    stdout.writeln('warning: $warning');
  }

  final written = await writeGeneratedFiles(result, outputDirectory);
  for (final path in written) {
    stdout.writeln('generated: $path');
  }
  stdout.writeln(
    '${result.files.length} Dart file(s) and openapi.json written to '
    '"$outputDirectory".',
  );
}

Future<void> _diff(ArgResults options) async {
  final baseDirectory = options.option('base');
  final candidateDirectory = options.option('candidate');
  if (baseDirectory == null || candidateDirectory == null) {
    stderr.writeln('Both --base and --candidate are required.');
    exitCode = 64;
    return;
  }

  final base = await _loadContract(baseDirectory);
  final candidate = await _loadContract(candidateDirectory);

  final diff = diffContracts(base, candidate);
  final quiet = options.flag('quiet');
  final changes = quiet ? diff.breakingChanges : diff.changes;

  if (changes.isEmpty) {
    stdout.writeln('No changes detected.');
    return;
  }

  for (final change in changes) {
    stdout.writeln(change.toString());
  }
  stdout.writeln();
  stdout.writeln(
    '${diff.breakingChanges.length} breaking change(s), '
    '${diff.changes.length - diff.breakingChanges.length} non-breaking '
    'change(s).',
  );

  if (diff.hasBreakingChanges) {
    exitCode = 1;
  }
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
  );
  stdout.write(result.stdout);
  if (result.exitCode != 0) {
    stderr.write(result.stderr);
    exitCode = result.exitCode;
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
      'LASKA_MIGRATIONS_DIRECTORY': options.option('directory')!,
    },
  );
  stdout.write(result.stdout);
  if (result.exitCode != 0) {
    stderr.write(result.stderr);
    exitCode = result.exitCode;
  }
}

/// Runs the workspace in development.
///
/// Every service of the manifest is started, the logs of the services are
/// aggregated in one stream and the telemetry of the services is sent to the
/// local collector, which prints the traces it receives.
Future<void> _dev(ArgResults options) async {
  final manifest = File(options.option('manifest')!);
  final services = <WorkspaceService>[];

  if (manifest.existsSync()) {
    try {
      services.addAll(readWorkspace(manifest).services);
    } on WorkspaceException catch (error) {
      stderr.writeln(error.message);
      exitCode = 65;
      return;
    }
  } else {
    final entrypoint = _resolveEntrypoint(options.option('entrypoint'));
    if (entrypoint == null) {
      return;
    }
    services.add(
      WorkspaceService(
        name: 'app',
        entrypoint: entrypoint,
        port: int.tryParse(options.option('port') ?? '') ?? 3789,
      ),
    );
  }

  // The entrypoints are checked before anything is started, so a wrong
  // manifest costs nothing.
  for (final service in services) {
    if (!File(service.entrypoint).existsSync()) {
      stderr.writeln(
        'The entrypoint "${service.entrypoint}" of the service '
        '"${service.name}" does not exist.',
      );
      exitCode = 66;
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
      stderr.writeln('The collector could not start: ${error.message}');
      exitCode = 69;
      return;
    }
    stdout.writeln('=> collector on ${collector.endpoint}');
  }

  final supervisors = <Supervisor>[];
  try {
    for (final service in services) {
      final entrypoint = File(service.entrypoint);

      stdout.writeln(
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
            ...service.environment,
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

    stdout.writeln(
      '=> ${services.length} service(s) started. Press Ctrl+C to stop.',
    );

    await Completer<void>().future;
  } finally {
    // The collector holds the event loop of the process, so it is closed when
    // the command returns.
    await collector?.stop();
  }
}

/// Resolves the entrypoint of the service.
///
/// Returns `null` and reports the problem when no entrypoint can be found.
String? _resolveEntrypoint(String? option) {
  if (option != null) {
    final file = File(option);
    if (!file.existsSync()) {
      stderr.writeln('The entrypoint "$option" does not exist.');
      exitCode = 66;
      return null;
    }
    return file.absolute.path;
  }

  for (final candidate in const <String>['bin/server.dart', 'bin/main.dart']) {
    final file = File(candidate);
    if (file.existsSync()) {
      return file.absolute.path;
    }
  }

  stderr.writeln(
    'No entrypoint found. Pass --entrypoint with the Dart file of the service.',
  );
  exitCode = 66;
  return null;
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
