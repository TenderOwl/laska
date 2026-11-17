import 'dart:io';

import '../logger.dart';
import 'database.dart';

/// A single migration file.
class Migration {
  /// Creates a migration.
  Migration({
    required this.version,
    required this.name,
    required this.up,
    this.down,
  });

  /// The version of the migration, e.g. `001`.
  final String version;

  /// The name of the migration, e.g. `create_users`.
  final String name;

  /// The SQL applied when the migration runs.
  final String up;

  /// The SQL applied when the migration is rolled back.
  final String? down;

  /// The identifier used in the ledger.
  String get id => '${version}_$name';
}

/// Applies the SQL migrations of a service.
///
/// Migrations are plain `.sql` files in a directory, named
/// `<version>_<name>.sql`. They are applied in order and recorded in a
/// `schema_migrations` table, so a migration is never applied twice.
///
/// A file may hold a rollback section after a `-- @down` marker:
///
/// ```sql
/// CREATE TABLE users (id INTEGER PRIMARY KEY);
/// -- @down
/// DROP TABLE users;
/// ```
class MigrationRunner {
  /// Creates a runner for [database].
  MigrationRunner(
    this.database, {
    this.directory = 'migrations',
    this.table = 'schema_migrations',
  });

  /// The database the migrations are applied to.
  final Database database;

  /// The directory holding the `.sql` files.
  final String directory;

  /// The name of the ledger table.
  final String table;

  /// The migrations found in [directory], ordered by version.
  Future<List<Migration>> migrations() async {
    final dir = Directory(directory);
    if (!dir.existsSync()) {
      return const <Migration>[];
    }

    final files = dir
        .listSync()
        .whereType<File>()
        .where((file) => file.path.endsWith('.sql'))
        .toList()
      ..sort((a, b) => a.path.compareTo(b.path));

    return files.map(_parse).toList();
  }

  /// The versions that were already applied.
  Future<List<String>> applied() async {
    await _createLedger();
    final rows = await database.query('SELECT version FROM $table');
    return rows.map((row) => row['version']! as String).toList();
  }

  /// The migrations that were not applied yet.
  Future<List<Migration>> pending() async {
    final appliedVersions = (await applied()).toSet();
    final known = await migrations();
    return known
        .where((migration) => !appliedVersions.contains(migration.id))
        .toList();
  }

  /// Applies every pending migration.
  ///
  /// Returns the migrations that were applied.
  Future<List<Migration>> migrate({Logger? logger}) async {
    await _createLedger();
    final pendingMigrations = await pending();
    final appliedMigrations = <Migration>[];

    for (final migration in pendingMigrations) {
      logger?.info('applying migration ${migration.id}');
      await database.transaction((transaction) async {
        await _runSql(transaction, migration.up);
        await transaction.execute(
          'INSERT INTO $table (version, name, applied_at) VALUES (?, ?, ?)',
          <Object?>[
            migration.id,
            migration.name,
            DateTime.now().toUtc().toIso8601String(),
          ],
        );
      });
      appliedMigrations.add(migration);
    }

    return appliedMigrations;
  }

  /// Rolls the last [steps] migrations back.
  ///
  /// Returns the migrations that were rolled back.
  Future<List<Migration>> rollback({int steps = 1, Logger? logger}) async {
    await _createLedger();
    final rows = await database.query(
      'SELECT version, name FROM $table ORDER BY version DESC LIMIT ?',
      <Object?>[steps],
    );
    if (rows.isEmpty) {
      return const <Migration>[];
    }

    final known = <String, Migration>{
      for (final migration in await migrations()) migration.id: migration,
    };
    final rolledBack = <Migration>[];
    for (final row in rows) {
      final id = row['version']! as String;
      final migration = known[id];
      if (migration != null && migration.down != null) {
        logger?.info('rolling back migration ${migration.id}');
        await database.transaction((transaction) async {
          await _runSql(transaction, migration.down!);
          await transaction.execute(
            'DELETE FROM $table WHERE version = ?',
            <Object?>[id],
          );
        });
      } else {
        logger?.warning(
          'migration ${migration?.id ?? id} has no rollback section, '
          'removing it from the ledger only',
        );
        await database.execute(
          'DELETE FROM $table WHERE version = ?',
          <Object?>[id],
        );
      }
      rolledBack.add(
        migration ??
            Migration(
              version: id,
              name: row['name']! as String,
              up: '',
            ),
      );
    }

    return rolledBack;
  }

  Future<void> _createLedger() async {
    await database.execute(
      'CREATE TABLE IF NOT EXISTS $table ('
      'version TEXT PRIMARY KEY, '
      'name TEXT NOT NULL, '
      'applied_at TEXT NOT NULL'
      ')',
    );
  }

  Future<void> _runSql(Database database, String sql) async {
    for (final statement in _splitStatements(sql)) {
      await database.execute(statement);
    }
  }

  Migration _parse(File file) {
    final name = file.uri.pathSegments.last.replaceAll('.sql', '');
    final separator = name.indexOf('_');
    final version = separator == -1 ? name : name.substring(0, separator);
    final migrationName = separator == -1 ? '' : name.substring(separator + 1);

    final content = file.readAsStringSync();
    final downMarker = content.indexOf('-- @down');
    final up = downMarker == -1 ? content : content.substring(0, downMarker);
    final down = downMarker == -1
        ? null
        : content.substring(downMarker + '-- @down'.length);

    return Migration(
      version: version,
      name: migrationName,
      up: up.trim(),
      down: down?.trim(),
    );
  }

  static List<String> _splitStatements(String sql) {
    return sql
        .split(';')
        .map((statement) => statement.trim())
        .where((statement) => statement.isNotEmpty)
        .toList();
  }
}
