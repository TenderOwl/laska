import 'package:args/args.dart';

/// The version of the CLI.
const String cliVersion = '0.1.0';

/// Builds the parser of the CLI.
///
/// The parser is the single source of truth of the commands and of the
/// options, so the help stays in sync with the parser.
ArgParser buildParser() {
  final parser = ArgParser()
    ..addFlag(
      'version',
      negatable: false,
      help: 'Print the version of the CLI.',
    );
  addHelpFlag(parser);

  final contract = parser.addCommand('contract');
  addHelpFlag(contract);

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
  addHelpFlag(compile);

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
  addHelpFlag(diff);

  final serve = parser.addCommand('serve')
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
  addHelpFlag(serve);

  final routeList = parser.addCommand('route:list');
  routeList.addOption(
    'entrypoint',
    help: 'Dart file of the service. Defaults to bin/server.dart.',
  );
  addHelpFlag(routeList);

  final migrate = parser.addCommand('migrate:run')
    ..addOption(
      'entrypoint',
      help: 'Dart file of the service. Defaults to bin/server.dart.',
    )
    ..addOption(
      'directory',
      help: 'Directory holding the migration files.',
      defaultsTo: 'migrations',
    );
  addHelpFlag(migrate);

  final dev = parser.addCommand('dev')
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
  addHelpFlag(dev);

  parser.addCommand('help');

  return parser;
}

/// Adds the `--help` flag to [parser].
void addHelpFlag(ArgParser parser) {
  parser.addFlag(
    'help',
    abbr: 'h',
    negatable: false,
    help: 'Print this help.',
  );
}
