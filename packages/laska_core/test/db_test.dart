import 'dart:io';

import 'package:laska_core/laska_core.dart';
import 'package:test/test.dart';

void main() {
  late SqliteDatabase database;

  setUp(() {
    database = SqliteDatabase.memory();
  });

  tearDown(() async {
    await database.close();
  });

  group('SqliteDatabase', () {
    test('runs a statement', () async {
      final affected = await database.execute(
        'CREATE TABLE users (id INTEGER PRIMARY KEY, name TEXT NOT NULL)',
      );

      expect(affected, isNonNegative);
    });

    test('queries the rows of a table', () async {
      await database.execute(
        'CREATE TABLE users (id INTEGER PRIMARY KEY, name TEXT NOT NULL)',
      );
      await database.execute(
        'INSERT INTO users (id, name) VALUES (?, ?)',
        <Object?>[1, 'Ada'],
      );

      final rows = await database.query('SELECT id, name FROM users');

      expect(rows, hasLength(1));
      expect(rows.first['id'], 1);
      expect(rows.first['name'], 'Ada');
    });

    test('returns an empty list when nothing matches', () async {
      await database.execute(
        'CREATE TABLE users (id INTEGER PRIMARY KEY, name TEXT NOT NULL)',
      );

      final rows = await database.query('SELECT id FROM users');

      expect(rows, isEmpty);
    });

    test('commits a transaction', () async {
      await database.execute(
        'CREATE TABLE users (id INTEGER PRIMARY KEY, name TEXT NOT NULL)',
      );

      await database.transaction((transaction) async {
        await transaction.execute(
          'INSERT INTO users (id, name) VALUES (?, ?)',
          <Object?>[1, 'Ada'],
        );
      });

      final rows = await database.query('SELECT id FROM users');
      expect(rows, hasLength(1));
    });

    test('rolls a failed transaction back', () async {
      await database.execute(
        'CREATE TABLE users (id INTEGER PRIMARY KEY, name TEXT NOT NULL)',
      );

      await expectLater(
        database.transaction((transaction) async {
          await transaction.execute(
            'INSERT INTO users (id, name) VALUES (?, ?)',
            <Object?>[1, 'Ada'],
          );
          throw StateError('the service failed');
        }),
        throwsA(isA<DatabaseException>()),
      );

      final rows = await database.query('SELECT id FROM users');
      expect(rows, isEmpty);
    });

    test('keeps the refusal of the service inside a transaction', () async {
      await database.execute(
        'CREATE TABLE users (id INTEGER PRIMARY KEY, name TEXT NOT NULL)',
      );

      // The refusal of the service carries the status the caller has to see,
      // so the transaction may not turn it into a failure of the database.
      await expectLater(
        database.transaction((transaction) async {
          await transaction.execute(
            'INSERT INTO users (id, name) VALUES (?, ?)',
            <Object?>[1, 'Ada'],
          );
          throw HttpException(422, 'The account does not hold the money.');
        }),
        throwsA(isA<HttpException>()),
      );

      final rows = await database.query('SELECT id FROM users');
      expect(rows, isEmpty);
    });

    test('answers the ping', () async {
      expect(await database.ping(), isTrue);
    });

    test('reports a broken statement', () async {
      await expectLater(
        database.query('SELECT * FROM nowhere'),
        throwsA(isA<DatabaseException>()),
      );
    });
  });

  group('MigrationRunner', () {
    late Directory directory;

    setUp(() {
      directory = Directory.systemTemp.createTempSync('laska_migrations_');
    });

    tearDown(() {
      if (directory.existsSync()) {
        directory.deleteSync(recursive: true);
      }
    });

    void writeMigration(String name, String content) {
      File('${directory.path}/$name').writeAsStringSync(content);
    }

    test('finds the migrations of the directory', () async {
      writeMigration('001_create_users.sql', 'CREATE TABLE users (id INT);');
      writeMigration('002_add_name.sql', 'ALTER TABLE users ADD name TEXT;');

      final runner = MigrationRunner(database, directory: directory.path);
      final migrations = await runner.migrations();

      expect(migrations.map((migration) => migration.id), <String>[
        '001_create_users',
        '002_add_name',
      ]);
    });

    test('applies the migrations and records them', () async {
      writeMigration('001_create_users.sql', 'CREATE TABLE users (id INT);');

      final runner = MigrationRunner(database, directory: directory.path);
      final applied = await runner.migrate();

      expect(applied, hasLength(1));
      expect(applied.single.id, '001_create_users');

      final rows =
          await database.query('SELECT version FROM schema_migrations');
      expect(rows.single['version'], '001_create_users');
    });

    test('never applies a migration twice', () async {
      writeMigration('001_create_users.sql', 'CREATE TABLE users (id INT);');

      final runner = MigrationRunner(database, directory: directory.path);
      await runner.migrate();
      final applied = await runner.migrate();

      expect(applied, isEmpty);
    });

    test('applies the pending migrations only', () async {
      writeMigration('001_create_users.sql', 'CREATE TABLE users (id INT);');

      final runner = MigrationRunner(database, directory: directory.path);
      await runner.migrate();

      writeMigration('002_add_name.sql', 'ALTER TABLE users ADD name TEXT;');
      final applied = await runner.migrate();

      expect(applied, hasLength(1));
      expect(applied.single.id, '002_add_name');
    });

    test('rolls a migration back', () async {
      writeMigration(
        '001_create_users.sql',
        'CREATE TABLE users (id INT);\n-- @down\nDROP TABLE users;',
      );

      final runner = MigrationRunner(database, directory: directory.path);
      await runner.migrate();

      final rolledBack = await runner.rollback();

      expect(rolledBack.single.id, '001_create_users');
      final rows =
          await database.query('SELECT version FROM schema_migrations');
      expect(rows, isEmpty);
    });

    test('keeps a migration without a rollback section in the ledger',
        () async {
      writeMigration('001_create_users.sql', 'CREATE TABLE users (id INT);');

      final runner = MigrationRunner(database, directory: directory.path);
      await runner.migrate();
      final rolledBack = await runner.rollback();

      expect(rolledBack.single.id, '001_create_users');
      final rows =
          await database.query('SELECT version FROM schema_migrations');
      expect(rows, isEmpty);
    });

    test('does nothing when the directory is missing', () async {
      final runner = MigrationRunner(
        database,
        directory: '${directory.path}/missing',
      );

      expect(await runner.migrations(), isEmpty);
      expect(await runner.migrate(), isEmpty);
    });
  });
}
