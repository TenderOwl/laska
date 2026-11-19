import 'package:laska_core/laska_core.dart';

import 'app.dart';
import 'database.dart';

/// Starts the example service.
///
/// The database is a file next to the service, and the migrations are applied
/// before the service answers, so a fresh deployment comes up with the schema
/// it needs. The migrations may also be applied on their own, with the flag
/// `--laska-migrate` — the same path the command `laska migrate:run` takes:
///
/// ```console
/// $ dart run lib/main.dart --laska-migrate
/// ```
Future<void> main(List<String> arguments) async {
  final database = await openDatabase(path: 'laska.db');
  final app = await buildApp(database: database);

  await run(app, arguments: arguments, port: 8080);
}
