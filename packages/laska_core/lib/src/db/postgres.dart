import 'dart:io';

import 'package:postgres/postgres.dart';

import 'database.dart';

/// A PostgreSQL database backed by a connection pool.
class PostgresDatabase implements Database {
  /// Creates a database on top of an existing [pool].
  PostgresDatabase(this._pool);

  /// Connects to a PostgreSQL server and opens a pool.
  factory PostgresDatabase.connect({
    required String host,
    int port = 5432,
    required String database,
    String? username,
    String? password,
    int poolSize = 10,
    Duration? connectTimeout,
    String? applicationName,
  }) {
    final pool = Pool.withEndpoints(
      <Endpoint>[
        Endpoint(
          host: host,
          port: port,
          database: database,
          username: username,
          password: password,
        ),
      ],
      settings: PoolSettings(
        maxConnectionCount: poolSize,
        connectTimeout: connectTimeout,
        applicationName: applicationName,
      ),
    );
    return PostgresDatabase(pool);
  }

  final Pool _pool;

  /// Connects using the values of the environment.
  ///
  /// Reads `DATABASE_HOST`, `DATABASE_PORT`, `DATABASE_NAME`,
  /// `DATABASE_USER` and `DATABASE_PASSWORD`.
  factory PostgresDatabase.fromEnvironment({
    int poolSize = 10,
    String? host,
    int? port,
    String? database,
    String? username,
    String? password,
  }) {
    return PostgresDatabase.connect(
      host: host ?? Platform.environment['DATABASE_HOST'] ?? 'localhost',
      port: port ??
          int.tryParse(Platform.environment['DATABASE_PORT'] ?? '') ??
          5432,
      database: database ?? Platform.environment['DATABASE_NAME'] ?? 'postgres',
      username: username ?? Platform.environment['DATABASE_USER'],
      password: password ?? Platform.environment['DATABASE_PASSWORD'],
      poolSize: poolSize,
    );
  }

  @override
  Future<List<Map<String, Object?>>> query(
    String sql, [
    List<Object?> parameters = const <Object?>[],
  ]) async {
    try {
      final result = await _pool.run(
        (session) => session.execute(sql, parameters: parameters),
      );
      return result.map((row) => row.toColumnMap()).toList();
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
      final result = await _pool.run(
        (session) => session.execute(sql, parameters: parameters),
      );
      return result.affectedRows;
    } catch (error) {
      throw DatabaseException('Statement failed: $sql', cause: error);
    }
  }

  @override
  Future<T> transaction<T>(
    Future<T> Function(Database transaction) action,
  ) async {
    try {
      return await _pool.runTx((session) async {
        return action(_SessionDatabase(session));
      });
    } catch (error) {
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
  Future<void> close() => _pool.close();
}

class _SessionDatabase implements Database {
  _SessionDatabase(this._session);

  final Session _session;

  @override
  Future<List<Map<String, Object?>>> query(
    String sql, [
    List<Object?> parameters = const <Object?>[],
  ]) async {
    final result = await _session.execute(sql, parameters: parameters);
    return result.map((row) => row.toColumnMap()).toList();
  }

  @override
  Future<int> execute(
    String sql, [
    List<Object?> parameters = const <Object?>[],
  ]) async {
    final result = await _session.execute(sql, parameters: parameters);
    return result.affectedRows;
  }

  @override
  Future<T> transaction<T>(
    Future<T> Function(Database transaction) action,
  ) =>
      action(this);

  @override
  Future<bool> ping() async {
    await query('SELECT 1');
    return true;
  }

  @override
  Future<void> close() async {}
}
