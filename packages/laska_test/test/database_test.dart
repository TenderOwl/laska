import 'package:laska_core/laska_core.dart';
import 'package:laska_test/laska_test.dart';
import 'package:test/test.dart';

void main() {
  group('openTestDatabase', () {
    test('opens an in-memory database', () async {
      final database = await openTestDatabase();

      await database.execute(
        'CREATE TABLE users (id INTEGER PRIMARY KEY, name TEXT NOT NULL)',
      );
      await database.execute(
        'INSERT INTO users (id, name) VALUES (?, ?)',
        <Object?>[1, 'Ada'],
      );

      final rows = await database.query('SELECT name FROM users');
      await database.close();

      expect(rows.single['name'], 'Ada');
    });
  });

  group('withTestDatabase', () {
    late SqliteDatabase database;

    setUp(() async {
      database = await openTestDatabase();
      await database.execute(
        'CREATE TABLE users (id INTEGER PRIMARY KEY, name TEXT NOT NULL)',
      );
    });

    tearDown(() async {
      await database.close();
    });

    test('lets the test see the data it wrote', () async {
      final name = await withTestDatabase<String>(
        database,
        (transaction) async {
          await transaction.execute(
            'INSERT INTO users (id, name) VALUES (?, ?)',
            <Object?>[1, 'Ada'],
          );
          final rows = await transaction.query('SELECT name FROM users');
          return rows.single['name']! as String;
        },
      );

      expect(name, 'Ada');
    });

    test('rolls the data back afterwards', () async {
      await withTestDatabase<void>(
        database,
        (transaction) async {
          await transaction.execute(
            'INSERT INTO users (id, name) VALUES (?, ?)',
            <Object?>[1, 'Ada'],
          );
        },
      );

      final rows = await database.query('SELECT id FROM users');
      expect(rows, isEmpty);
    });

    test('reports the error of the body', () async {
      await expectLater(
        withTestDatabase<void>(
          database,
          (transaction) async {
            throw StateError('the service failed');
          },
        ),
        throwsA(isA<DatabaseException>()),
      );
    });
  });
}
