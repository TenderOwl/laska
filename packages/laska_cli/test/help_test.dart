import 'package:laska_cli/src/cli.dart';
import 'package:laska_cli/src/help.dart';
import 'package:laska_cli/src/parser.dart';
import 'package:test/test.dart';

void main() {
  final parser = buildParser();
  final help = LaskaHelp(parser: parser, version: cliVersion);

  group('the help of the CLI', () {
    test('lists every command of the parser', () {
      final text = help.root();

      for (final command in parser.commands.keys) {
        expect(text, contains(command));
      }
    });

    test('lists the subcommands of a command', () {
      final text = help.root();

      expect(text, contains('contract compile'));
      expect(text, contains('contract diff'));
    });

    test('describes every command of the parser', () {
      for (final command in parser.commands.keys) {
        expect(
          commandHelp[command],
          isNotNull,
          reason: 'the command "$command" has no description',
        );
        expect(commandHelp[command]!.summary, isNotEmpty);
      }
    });

    test('lists the global options', () {
      final text = help.root();

      expect(text, contains('--help'));
      expect(text, contains('--version'));
    });

    test('lists the environment variables of the telemetry', () {
      final text = help.root();

      expect(text, contains('OTEL_SERVICE_NAME'));
      expect(text, contains('OTEL_EXPORTER_OTLP_ENDPOINT'));
      expect(text, contains('OTEL_SDK_DISABLED'));
    });

    test('lists the examples', () {
      final text = help.root();

      expect(text, contains('Examples:'));
      expect(text, contains('laska contract compile'));
    });
  });

  group('the help of a command', () {
    test('lists the options of the command with their default', () {
      final text = help.command(<String>['contract', 'compile'])!;

      expect(text, contains('laska contract compile'));
      expect(text, contains('--proto'));
      expect(text, contains('(default: proto)'));
      expect(text, contains('--out'));
      expect(text, contains('(default: lib/generated)'));
    });

    test('lists the subcommands of a command', () {
      final text = help.command(<String>['contract'])!;

      expect(text, contains('compile'));
      expect(text, contains('diff'));
    });

    test('is null for a command that does not exist', () {
      expect(help.command(<String>['nosuch']), isNull);
      expect(help.command(<String>['contract', 'nosuch']), isNull);
    });
  });

  group('the command line interface', () {
    late StringBuffer out;
    late StringBuffer err;

    setUp(() {
      out = StringBuffer();
      err = StringBuffer();
    });

    Future<int> run(List<String> arguments) =>
        runCli(arguments, out: out, err: err);

    test('--help prints the list of the commands', () async {
      final code = await run(<String>['--help']);

      expect(code, 0);
      expect(err.toString(), isEmpty);
      expect(out.toString(), contains('Usage:'));
      expect(out.toString(), contains('contract compile'));
      expect(out.toString(), contains('route:list'));
      expect(out.toString(), contains('migrate:run'));
      expect(out.toString(), contains('dev'));
    });

    test('-h prints the same help as --help', () async {
      final code = await run(<String>['-h']);

      expect(code, 0);
      expect(out.toString(), contains('Usage:'));
      expect(out.toString(), contains('contract compile'));
    });

    test('without an argument the help of the CLI is printed', () async {
      final code = await run(<String>[]);

      expect(code, 0);
      expect(out.toString(), contains('Usage:'));
      expect(out.toString(), contains('contract compile'));
    });

    test('help prints the help of a command', () async {
      final code = await run(<String>['help', 'contract', 'compile']);

      expect(code, 0);
      expect(out.toString(), contains('laska contract compile'));
      expect(out.toString(), contains('--proto'));
    });

    test('a command answers --help on its own', () async {
      final code = await run(<String>['contract', 'compile', '--help']);

      expect(code, 0);
      expect(out.toString(), contains('laska contract compile'));
      expect(out.toString(), contains('--proto'));
    });

    test('a command answers -h on its own', () async {
      final code = await run(<String>['dev', '-h']);

      expect(code, 0);
      expect(out.toString(), contains('laska dev'));
      expect(out.toString(), contains('--manifest'));
    });

    test('help fails for a command that does not exist', () async {
      final code = await run(<String>['help', 'nosuch']);

      expect(code, 64);
      expect(err.toString(), contains('Unknown command "nosuch"'));
    });

    test('the run fails for a command that does not exist', () async {
      final code = await run(<String>['nosuch']);

      expect(code, 64);
      expect(err.toString(), contains('Unknown command "nosuch"'));
    });

    test('the run fails for a subcommand that does not exist', () async {
      final code = await run(<String>['contract', 'nosuch']);

      expect(code, 64);
      expect(err.toString(), contains('Unknown subcommand "nosuch"'));
    });

    test('the version is printed', () async {
      final code = await run(<String>['--version']);

      expect(code, 0);
      expect(out.toString(), 'laska $cliVersion\n');
    });
  });
}
