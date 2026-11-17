import 'dart:io';

import 'package:laska_core/laska_core.dart';

/// A service with a database, used by the CLI tests.
///
/// The `laska migrate:run` command runs it with a flag, so it applies the
/// migrations and exits.
Future<void> main(List<String> arguments) async {
  final path = Platform.environment['LASKA_TEST_DATABASE'] ??
      '${Directory.systemTemp.path}/laska_cli_migrate.sqlite';

  final app = Laska();
  app.database = SqliteDatabase.open(path);
  app.get('/users', (ctx) => ctx.text('ok'));

  await run(app, arguments: arguments);
}
