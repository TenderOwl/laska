import 'dart:io';

import 'package:laska_cli/src/cli.dart';

/// Entry point of the `laska` command line interface.
Future<void> main(List<String> arguments) async {
  exitCode = await runCli(arguments);
}
