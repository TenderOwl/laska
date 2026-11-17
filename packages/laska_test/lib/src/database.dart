import 'package:laska_core/laska_core.dart';

/// Runs [body] inside a transaction that is rolled back afterwards.
///
/// The test sees the data it wrote, the database does not keep it. This is
/// the cheapest way to isolate tests that touch a real database.
Future<T> withTestDatabase<T>(
  Database database,
  Future<T> Function(Database transaction) body,
) async {
  Object? result;
  try {
    await database.transaction((transaction) async {
      result = await body(transaction);
      throw const _Rollback();
    });
  } on DatabaseException catch (error) {
    // The database wraps the error of the transaction, so the sentinel of the
    // intentional rollback is found in the cause.
    if (error.cause is! _Rollback) {
      rethrow;
    }
  } on _Rollback {
    // The transaction was rolled back on purpose.
  }
  return result as T;
}

/// Opens an in-memory SQLite database for a test.
Future<SqliteDatabase> openTestDatabase({String? path}) async {
  return path == null ? SqliteDatabase.memory() : SqliteDatabase.open(path);
}

class _Rollback implements Exception {
  const _Rollback();
}
