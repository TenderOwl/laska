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

  final lint = contract.addCommand('lint')
    ..addOption(
      'proto',
      help: 'Directory containing the .proto files.',
      defaultsTo: 'api',
    );
  addHelpFlag(lint);

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
    )
    ..addOption(
      'startup-timeout',
      help: 'Seconds a service waits for the services it depends on.',
      defaultsTo: '30',
    );
  addHelpFlag(dev);

  final dockerfile = parser.addCommand('deploy:dockerfile')
    ..addOption(
      'manifest',
      help: 'Workspace manifest. Defaults to laska.yaml.',
      defaultsTo: 'laska.yaml',
    )
    ..addOption(
      'out',
      help: 'Directory the Dockerfiles are written to.',
      defaultsTo: 'deploy',
    )
    ..addOption(
      'image',
      help: 'Repository the images are pushed to.',
      defaultsTo: 'laska',
    );
  addHelpFlag(dockerfile);

  final kubernetes = parser.addCommand('deploy:k8s')
    ..addOption(
      'manifest',
      help: 'Workspace manifest. Defaults to laska.yaml.',
      defaultsTo: 'laska.yaml',
    )
    ..addOption(
      'out',
      help: 'Directory the manifests are written to.',
      defaultsTo: 'deploy',
    )
    ..addOption(
      'image',
      help: 'Repository the images are pulled from.',
      defaultsTo: 'laska',
    )
    ..addOption(
      'namespace',
      help: 'Namespace of the manifests.',
      defaultsTo: 'default',
    );
  addHelpFlag(kubernetes);

  final recipe = parser.addCommand('ci:recipe')
    ..addOption(
      'out',
      help: 'File the recipe is written to.',
      defaultsTo: '.github/workflows/laska.yml',
    )
    ..addOption(
      'proto',
      help: 'Directory containing the .proto files.',
      defaultsTo: 'api',
    )
    ..addOption(
      'base',
      help: 'Directory containing the baseline .proto files.',
    )
    ..addOption(
      'candidate',
      help: 'Directory containing the candidate .proto files.',
    );
  addHelpFlag(recipe);

  final create = parser.addCommand('new')
    ..addOption(
      'out',
      help: 'Directory the project is written to. Defaults to the current one.',
      defaultsTo: '.',
    )
    ..addOption(
      'port',
      help: 'Port the service listens to in development.',
      defaultsTo: '8080',
    )
    ..addOption(
      'manifest',
      help: 'Workspace manifest the service is added to.',
      defaultsTo: 'laska.yaml',
    )
    ..addFlag(
      'local',
      negatable: false,
      help: 'Depend on the packages of the local Laska workspace instead of '
          'the published ones.',
    );
  addHelpFlag(create);

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
