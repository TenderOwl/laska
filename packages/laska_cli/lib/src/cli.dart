import 'dart:async';
import 'dart:io';

import 'package:args/args.dart';
import 'package:laska_cli/src/collector.dart';
import 'package:laska_cli/src/help.dart';
import 'package:laska_cli/src/parser.dart';
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
      case 'serve':
        await _serve(command);
      case 'route:list':
        await _routeList(command);
      case 'migrate:run':
        await _migrate(command);
      case 'dev':
        await _dev(command);
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
      default:
        err.writeln('Unknown subcommand "${subcommand.name}".');
        code = 64;
    }
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

    if (diff.hasBreakingChanges) {
      code = 1;
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
        err.writeln(error.message);
        code = 65;
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
        err.writeln(
          'The entrypoint "${service.entrypoint}" of the service '
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
        final entrypoint = File(service.entrypoint);

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
