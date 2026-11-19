import 'dart:io';

import 'package:laska_core/laska_core.dart';

/// The directory the migrations are read from.
///
/// The environment variable lets the deployment point the service at its own
/// migrations, and the default keeps the directory of the package.
String get migrationsDirectory =>
    Platform.environment['LASKA_MIGRATIONS_DIRECTORY'] ?? 'migrations';

/// Opens the database of the service and applies the migrations.
///
/// The example uses SQLite, because it needs no server: the database of the
/// service is a file, and the test opens one in the memory. A service in
/// production talks to PostgreSQL, and the rest of the code does not change:
///
/// ```dart
/// final database = await PostgresDatabase.fromEnvironment();
/// ```
///
/// The migrations are plain `.sql` files named `<version>_<name>.sql`. They
/// are applied in the order of their version and recorded in the table
/// `schema_migrations`, so a migration is never applied twice — the service
/// may start as often as it likes.
Future<Database> openDatabase({
  String? path,
  bool applyMigrations = true,
}) async {
  final database =
      path == null ? SqliteDatabase.memory() : SqliteDatabase.open(path);

  if (applyMigrations) {
    final runner = MigrationRunner(database, directory: migrationsDirectory);
    await runner.migrate();
  }

  return database;
}
