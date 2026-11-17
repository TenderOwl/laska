import 'package:sqlite3/sqlite3.dart' as sqlite;

import 'database.dart';

/// A SQLite database.
///
/// SQLite is the database of the test harness and of local development; a
/// service in production talks to PostgreSQL.
class SqliteDatabase implements Database {
  /// Creates a database on top of an existing connection.
  SqliteDatabase(this._database);

  /// Opens the database at [path].
  factory SqliteDatabase.open(String path) =>
      SqliteDatabase(sqlite.sqlite3.open(path));

  /// Opens an in-memory database.
  factory SqliteDatabase.memory() =>
      SqliteDatabase(sqlite.sqlite3.openInMemory());

  final sqlite.Database _database;

  @override
  Future<List<Map<String, Object?>>> query(
    String sql, [
    List<Object?> parameters = const <Object?>[],
  ]) async {
    try {
      final result = _database.select(sql, parameters);
      return result.map((row) => Map<String, Object?>.from(row)).toList();
    } catch (error) {
      throw DatabaseException('Query failed: $sql', cause: error);
    }
  }

  @override
  Future<int> execute(
    String sql, [
    List<Object?> parameters = const <Object?>[],
  ]) async {
    try {
      _database.execute(sql, parameters);
      return _database.updatedRows;
    } catch (error) {
      throw DatabaseException('Statement failed: $sql', cause: error);
    }
  }

  @override
  Future<T> transaction<T>(
    Future<T> Function(Database transaction) action,
  ) async {
    _database.execute('BEGIN');
    try {
      final result = await action(this);
      _database.execute('COMMIT');
      return result;
    } catch (error) {
      _database.execute('ROLLBACK');
      if (error is DatabaseException) {
        rethrow;
      }
      throw DatabaseException('Transaction failed', cause: error);
    }
  }

  @override
  Future<bool> ping() async {
    try {
      await query('SELECT 1');
      return true;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<void> close() async {
    _database.close();
  }
}
