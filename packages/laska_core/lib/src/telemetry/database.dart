/// The tracing of the database layer.
library;

import '../db/database.dart';
import 'tracer.dart';

/// A database that creates a span for every statement.
///
/// The span belongs to the trace of the request that caused the statement, so
/// a slow query shows up in the trace of the request that ran it.
class TracingDatabase implements Database {
  /// Wraps [database] so every statement creates a span.
  TracingDatabase(
    this._database,
    this._tracer, {
    this.system = 'sql',
  });

  final Database _database;
  final Tracer _tracer;

  /// The name of the database system, e.g. `postgresql` or `sqlite`.
  final String system;

  @override
  Future<List<Map<String, Object?>>> query(
    String sql, [
    List<Object?> parameters = const <Object?>[],
  ]) async {
    final span = _tracer.startSpan(
      'db.query',
      kind: SpanKind.client,
      attributes: <String, Object?>{
        'db.system': system,
        'db.statement': sql,
      },
    );
    try {
      final rows = await _database.query(sql, parameters);
      span.setAttribute('db.response.returned_rows', rows.length);
      return rows;
    } catch (error, stackTrace) {
      span.recordError(error, stackTrace);
      rethrow;
    } finally {
      span.end();
    }
  }

  @override
  Future<int> execute(
    String sql, [
    List<Object?> parameters = const <Object?>[],
  ]) async {
    final span = _tracer.startSpan(
      'db.execute',
      kind: SpanKind.client,
      attributes: <String, Object?>{
        'db.system': system,
        'db.statement': sql,
      },
    );
    try {
      final affected = await _database.execute(sql, parameters);
      span.setAttribute('db.response.affected_rows', affected);
      return affected;
    } catch (error, stackTrace) {
      span.recordError(error, stackTrace);
      rethrow;
    } finally {
      span.end();
    }
  }

  @override
  Future<T> transaction<T>(
    Future<T> Function(Database transaction) action,
  ) async {
    final span = _tracer.startSpan(
      'db.transaction',
      kind: SpanKind.client,
      attributes: <String, Object?>{'db.system': system},
    );
    try {
      return await _database.transaction(
        (transaction) =>
            action(TracingDatabase(transaction, _tracer, system: system)),
      );
    } catch (error, stackTrace) {
      span.recordError(error, stackTrace);
      rethrow;
    } finally {
      span.end();
    }
  }

  @override
  Future<bool> ping() => _database.ping();

  @override
  Future<void> close() => _database.close();
}
