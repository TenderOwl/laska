import 'package:args/args.dart';

/// The width the help text is wrapped to.
const int _width = 80;

/// The description of one command of the CLI.
class CommandHelp {
  const CommandHelp({
    required this.summary,
    this.description = '',
    this.examples = const <String>[],
  });

  /// The one line summary of the command.
  final String summary;

  /// The longer description of the command.
  final String description;

  /// The example invocations of the command.
  final List<String> examples;
}

/// The description of the commands of the CLI, keyed by the path of the
/// command.
///
/// The paths are the ones of the parser, so `contract compile` describes the
/// `compile` command of the `contract` command.
const Map<String, CommandHelp> commandHelp = <String, CommandHelp>{
  'contract': CommandHelp(
    summary: 'Compile a contract and check that it stays compatible.',
    description:
        'The contract commands read the .proto files of a directory, validate '
        'them and generate the code of the service.',
  ),
  'contract compile': CommandHelp(
    summary: 'Generate the Dart code and the OpenAPI document of a contract.',
    description:
        'Reads the .proto files of the directory, validates the contract and '
        'writes the Dart message classes, the service interface, the REST '
        'projection, the typed client and the OpenAPI 3.1 document.',
    examples: <String>[
      'laska contract compile --proto api --out lib/generated',
    ],
  ),
  'contract sdk': CommandHelp(
    summary: 'Generate the SDK of a contract in another language.',
    description:
        'Reads the .proto files of the directory, validates the contract and '
        'writes the SDK of the contract in the language given with --lang. The '
        'SDK is a module of its own: it holds the messages of the contract, the '
        'clients of its services and the runtime they need, so a service '
        'written in that language depends on nothing but its standard library.',
    examples: <String>[
      'laska contract sdk --lang=go --proto api --out go',
      'laska contract sdk --lang=go --proto api --out go '
          '--module example.com/laska/users',
    ],
  ),
  'contract diff': CommandHelp(
    summary: 'Compare two contracts and report the breaking changes.',
    description:
        'Compares a baseline contract with a candidate contract. The command '
        'fails with the exit code 1 when a breaking change is found, so it '
        'can be used in a continuous integration pipeline.',
    examples: <String>[
      'laska contract diff --base api-v1 --candidate api-v2',
      'laska contract diff --base api-v1 --candidate api-v2 --quiet',
    ],
  ),
  'contract lint': CommandHelp(
    summary: 'Check a contract against the rules of the framework.',
    description:
        'Reads the .proto files of the directory and reports the problems of '
        'the contract: a package that is not versioned, a file that does not '
        'match its package, a message that is not written in PascalCase, a '
        'field that is not written in snake_case, a service that does not end '
        'with "Service". The command fails with the exit code 1 when it finds '
        'a problem, so it can be used in a continuous integration pipeline.',
    examples: <String>[
      'laska contract lint --proto api',
    ],
  ),
  'contract matrix': CommandHelp(
    summary: 'Write the compatibility matrix of the versions of a contract.',
    description:
        'Compares every version of a contract with every other one and tells '
        'which client works against which server. The rows of the matrix are '
        'the clients, the columns are the servers. A cell reads "yes" when the '
        'client works against the server, "partly" when the server lacks a part '
        'of what the client expects and "no" when the client cannot work '
        'against the server. The versions are read from the directories given '
        'with --version, or from the subdirectories of the directory given with '
        '--dir.',
    examples: <String>[
      'laska contract matrix --dir contracts',
      'laska contract matrix --version api/v1 --version api/v2 --out matrix.md',
    ],
  ),
  'serve': CommandHelp(
    summary: 'Run a service under the supervisor.',
    description:
        'Starts the service in worker processes. The workers share the port '
        'and a worker that crashes is restarted, until it crashed too often.',
    examples: <String>[
      'laska serve --entrypoint bin/server.dart --port 3789',
    ],
  ),
  'route:list': CommandHelp(
    summary: 'Print the route table of a service.',
    description:
        'Prints the routes of the service as a table, without opening a port.',
    examples: <String>[
      'laska route:list --entrypoint bin/server.dart',
    ],
  ),
  'migrate:run': CommandHelp(
    summary: 'Apply the SQL migrations of a service.',
    description:
        'Applies the .sql files of the migrations directory in order. The '
        'migrations that were already applied are skipped.',
    examples: <String>[
      'laska migrate:run --entrypoint bin/server.dart',
    ],
  ),
  'dev': CommandHelp(
    summary: 'Run every service of the workspace in development.',
    description:
        'Starts the services of the workspace manifest, aggregates their logs '
        'into one stream and sends their telemetry to a local collector, '
        'which prints the traces it receives. The services are started in the '
        'order of their dependencies, and every service gets the address of '
        'the other services in its environment.',
    examples: <String>[
      'laska dev',
      'laska dev --manifest laska.yaml',
    ],
  ),
  'new': CommandHelp(
    summary: 'Scaffold a service or a workspace.',
    description:
        'Writes a service that is ready to run: the contract, the generated '
        'code, the implementation, the entrypoint and a test. The service is '
        'added to the manifest of the workspace. With a name instead of the '
        'word "service", a whole workspace with a first service is written.',
    examples: <String>[
      'laska new service users',
      'laska new service users --port 8081',
      'laska new shop',
    ],
  ),
  'deploy:dockerfile': CommandHelp(
    summary: 'Write the Dockerfile of every service of the workspace.',
    description:
        'Writes one Dockerfile per service, built in two steps: the Dart SDK '
        'compiles the service and the runtime image holds the binary alone.',
    examples: <String>[
      'laska deploy:dockerfile --manifest laska.yaml',
    ],
  ),
  'deploy:k8s': CommandHelp(
    summary: 'Write the Kubernetes manifests of every service.',
    description:
        'Writes the deployment and the service of every service of the '
        'workspace, so the cluster runs the same services as the workspace.',
    examples: <String>[
      'laska deploy:k8s --manifest laska.yaml --namespace laska',
    ],
  ),
  'ci:recipe': CommandHelp(
    summary: 'Write the recipe of the continuous integration.',
    description:
        'Writes a workflow that runs the format, the analyzer, the tests, the '
        'lint of the contract and the comparison of the contract with its '
        'baseline.',
    examples: <String>[
      'laska ci:recipe --out .github/workflows/laska.yml',
      'laska ci:recipe --base contracts/v1 --candidate contracts/v2',
      'laska ci:recipe --matrix contracts',
    ],
  ),
  'keys': CommandHelp(
    summary: 'Manage the keys of the service.',
    description:
        'The key commands make the keys that sign and verify the tokens of the '
        'service. The keys are written in the JWK format, so the service may '
        'publish its key set and the callers may fetch it.',
  ),
  'keys generate': CommandHelp(
    summary: 'Generate a key of the service.',
    description:
        'Generates a key and writes it in the given directory. The private key '
        'goes to a file of its own and the key set of the service goes to '
        'jwks.json next to it. The private file holds a secret, so it must not '
        'be published. A key that is generated again with the same id replaces '
        'the old one in the key set, which is how a service rotates its keys.',
    examples: <String>[
      'laska keys generate --alg rs256 --out keys',
      'laska keys generate --alg es256 --out keys --kid auth-2026',
    ],
  ),
  'upgrade': CommandHelp(
    summary: 'Move a service to a new version.',
    description:
        'With --api, the command moves the contract, the generated code and '
        'the calls of the service to the new version of the API, so a '
        'breaking change goes live next to the old one. Without it, the '
        'command runs the codemods of the step of the framework. Run it with '
        '--dry-run first to see what it would change.',
    examples: <String>[
      'laska upgrade --api users --from v1 --to v2',
      'laska upgrade --api users --from v1 --to v2 --dry-run',
      'laska upgrade --from 0.1.0 --to 0.2.0',
    ],
  ),
  'help': CommandHelp(
    summary: 'Print the help of the CLI or of one command.',
    description:
        'Without an argument the help of the CLI is printed. With the path of '
        'a command the help of that command is printed.',
    examples: <String>[
      'laska help',
      'laska help contract compile',
    ],
  ),
};

/// One line of a two column list of the help.
class _Entry {
  const _Entry(this.name, this.description, [this.note = '']);

  /// The name of the entry, the command or the option.
  final String name;

  /// The description of the entry.
  final String description;

  /// The note of the entry, the default value of an option.
  final String note;
}

/// The help of the CLI.
///
/// The commands and the options are read from the parser, so the help stays
/// in sync with the parser, and their descriptions come from [commandHelp].
class LaskaHelp {
  const LaskaHelp({required this.parser, required this.version});

  /// The parser of the CLI.
  final ArgParser parser;

  /// The version of the CLI.
  final String version;

  /// The help of the CLI itself.
  String root() {
    final buffer = StringBuffer();
    buffer.writeln('laska $version — the command line interface of Laska.');
    buffer.writeln();
    _writeParagraph(
      buffer,
      'Laska turns a protobuf contract into a REST service, a typed Dart '
      'client and an OpenAPI 3.1 document.',
    );
    buffer.writeln();
    buffer.writeln('Usage:');
    buffer.writeln('  laska <command> [options]');
    buffer.writeln('  laska help [command]');
    buffer.writeln();
    buffer.writeln('Commands:');
    _writeEntries(buffer, _commands());
    buffer.writeln();
    buffer.writeln('Global options:');
    _writeEntries(buffer, _options(parser));
    buffer.writeln();
    buffer.writeln('Environment:');
    _writeEntries(buffer, _environment());
    buffer.writeln();
    buffer.writeln('Examples:');
    for (final example in _examples()) {
      buffer.writeln('  $example');
    }
    return buffer.toString();
  }

  /// The help of the command at [path].
  ///
  /// Returns `null` when the path does not name a command.
  String? command(List<String> path) {
    final target = _parserFor(path);
    if (target == null) {
      return null;
    }

    final key = path.join(' ');
    final help = commandHelp[key];

    final buffer = StringBuffer();
    final summary = help?.summary;
    buffer.writeln(summary == null ? 'laska $key' : 'laska $key — $summary');
    if (help != null && help.description.isNotEmpty) {
      buffer.writeln();
      _writeParagraph(buffer, help.description);
    }
    buffer.writeln();
    buffer.writeln('Usage:');
    buffer.writeln('  laska $key [options]');

    if (target.commands.isNotEmpty) {
      buffer.writeln();
      buffer.writeln('Commands:');
      _writeEntries(
        buffer,
        target.commands.entries
            .map(
              (entry) => _Entry(
                entry.key,
                commandHelp['$key ${entry.key}']?.summary ?? '',
              ),
            )
            .toList(),
      );
    }

    final options = _options(target);
    if (options.isNotEmpty) {
      buffer.writeln();
      buffer.writeln('Options:');
      _writeEntries(buffer, options);
    }

    if (help != null && help.examples.isNotEmpty) {
      buffer.writeln();
      buffer.writeln('Examples:');
      for (final example in help.examples) {
        buffer.writeln('  $example');
      }
    }

    return buffer.toString();
  }

  /// The commands of the CLI, with the subcommands of a command listed under
  /// the path of that command.
  List<_Entry> _commands() {
    final entries = <_Entry>[];
    for (final entry in parser.commands.entries) {
      final help = commandHelp[entry.key];
      entries.add(_Entry(entry.key, help?.summary ?? ''));
      for (final subcommand in entry.value.commands.keys) {
        final subHelp = commandHelp['${entry.key} $subcommand'];
        entries.add(_Entry('${entry.key} $subcommand', subHelp?.summary ?? ''));
      }
    }
    return entries;
  }

  /// The options of [target], with their help and their default value.
  List<_Entry> _options(ArgParser target) {
    final entries = <_Entry>[];
    for (final option in target.options.values) {
      if (option.hide) {
        continue;
      }
      final names = <String>[
        if (option.abbr != null) '-${option.abbr}',
        if (option.isFlag)
          '--${option.name}'
        else
          '--${option.name} <${option.valueHelp ?? 'value'}>',
      ];

      final defaultValue = option.isFlag
          ? (option.defaultsTo == true ? 'true' : null)
          : option.defaultsTo;

      entries.add(
        _Entry(
          names.join(', '),
          option.help ?? '',
          defaultValue == null ? '' : '(default: $defaultValue)',
        ),
      );
    }
    return entries;
  }

  /// The environment variables the CLI and the services read.
  List<_Entry> _environment() => const <_Entry>[
        _Entry('OTEL_SERVICE_NAME', 'The name of the service in the traces.'),
        _Entry(
          'OTEL_EXPORTER_OTLP_ENDPOINT',
          'The endpoint of the OTLP collector. The telemetry stays off while '
              'it is not set.',
        ),
        _Entry(
          'OTEL_EXPORTER_OTLP_PROTOCOL',
          'The protocol of the collector: http/json or grpc.',
        ),
        _Entry(
          'OTEL_TRACES_SAMPLER_ARG',
          'The ratio of the traces that are recorded, between 0 and 1.',
        ),
        _Entry('OTEL_SDK_DISABLED', 'Turns the whole telemetry off.'),
        _Entry(
          'LASKA_MIGRATIONS_DIRECTORY',
          'The directory the SQL migrations are read from.',
        ),
        _Entry(
          'LASKA_SERVICES',
          'The addresses of the services of the workspace, as "name=url" pairs '
              'separated by commas.',
        ),
        _Entry(
          '<NAME>_URL',
          'The address of one service. `laska dev` sets it for every service '
              'of the workspace, so the discovery finds them.',
        ),
      ];

  /// The example invocations of the CLI.
  List<String> _examples() => const <String>[
        'laska contract compile --proto api --out lib/generated',
        'laska contract diff --base api-v1 --candidate api-v2',
        'laska route:list --entrypoint bin/server.dart',
        'laska migrate:run --entrypoint bin/server.dart',
        'laska dev',
      ];

  /// The parser of the command at [path], or `null` when the path does not
  /// name a command.
  ArgParser? _parserFor(List<String> path) {
    var target = parser;
    for (final name in path) {
      final child = target.commands[name];
      if (child == null) {
        return null;
      }
      target = child;
    }
    return target;
  }

  /// Writes the entries as a two column list, wrapped to [_width].
  void _writeEntries(StringBuffer buffer, List<_Entry> entries) {
    if (entries.isEmpty) {
      return;
    }

    final nameWidth = entries.fold<int>(
      0,
      (width, entry) => entry.name.length > width ? entry.name.length : width,
    );
    final column = 2 + nameWidth + 2;

    for (final entry in entries) {
      if (entry.description.isEmpty && entry.note.isEmpty) {
        buffer.writeln('  ${entry.name}');
        continue;
      }

      final padding = ' ' * (nameWidth - entry.name.length);
      final lines = _wrap(entry.description, _width - column);
      if (lines.isEmpty) {
        buffer.writeln('  ${entry.name}');
      } else {
        buffer.writeln('  ${entry.name}$padding  ${lines.first}');
        for (final line in lines.skip(1)) {
          buffer.writeln('${' ' * column}$line');
        }
      }
      if (entry.note.isNotEmpty) {
        for (final line in _wrap(entry.note, _width - column)) {
          buffer.writeln('${' ' * column}$line');
        }
      }
    }
  }

  /// Writes [text] as a paragraph, wrapped to [_width].
  void _writeParagraph(StringBuffer buffer, String text) {
    for (final line in _wrap(text, _width)) {
      buffer.writeln(line);
    }
  }

  /// Wraps [text] to [width] columns.
  List<String> _wrap(String text, int width) {
    final words =
        text.split(RegExp(r'\s+')).where((word) => word.isNotEmpty).toList();
    if (words.isEmpty) {
      return const <String>[];
    }

    final lines = <String>[];
    var line = '';
    for (final word in words) {
      if (line.isEmpty) {
        line = word;
      } else if (line.length + 1 + word.length <= width) {
        line = '$line $word';
      } else {
        lines.add(line);
        line = word;
      }
    }
    if (line.isNotEmpty) {
      lines.add(line);
    }
    return lines;
  }
}
