import 'dart:io';

import 'package:args/args.dart';
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
    default:
      stdout.writeln(parser.usage);
      exitCode = 64;
  }
}

({ArgParser parser, ArgParser compile, ArgParser diff}) _buildParser() {
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

  // Referenced by the usage output.
  return (parser: parser, compile: compile, diff: diff);
}

Future<void> _runContract(
  ArgResults command,
  ({ArgParser parser, ArgParser compile, ArgParser diff}) commands,
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
