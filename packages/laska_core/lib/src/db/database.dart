/// A relational database.
///
/// The framework does not own the data model, but it does own the boring
/// parts of talking to a database: pooling, transactions and type mapping.
library;

/// A relational database.
abstract class Database {
  /// Runs [sql] and returns the rows it produced.
  Future<List<Map<String, Object?>>> query(
    String sql, [
    List<Object?> parameters,
  ]);

  /// Runs [sql] and returns the number of affected rows.
  Future<int> execute(String sql, [List<Object?> parameters]);

  /// Runs [action] inside a transaction.
  ///
  /// The transaction is committed when [action] returns and rolled back when
  /// it throws.
  Future<T> transaction<T>(Future<T> Function(Database transaction) action);

  /// Whether the database answers.
  Future<bool> ping();

  /// Releases the resources of the database.
  Future<void> close();
}

/// Thrown when a database operation fails.
class DatabaseException implements Exception {
  /// Creates the exception.
  DatabaseException(this.message, {this.cause});

  /// Human readable description of the problem.
  final String message;

  /// The original error, when there was one.
  final Object? cause;

  @override
  String toString() =>
      'DatabaseException: $message${cause == null ? '' : ' ($cause)'}';
}
