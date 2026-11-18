/// The idempotency keys of the calls that change something.
///
/// A key travels with the request, so a caller that repeats a call after a
/// timeout does not change the world twice. The service that receives the key
/// answers the repeated call with the answer of the first one.
library;

import 'dart:math';

import '../middleware.dart';
import '../response.dart';

/// The header the idempotency key travels in.
const String idempotencyKeyHeader = 'idempotency-key';

final Random _random = Random.secure();

/// Creates a new idempotency key.
///
/// The key is random, so two calls never share one by accident.
String newIdempotencyKey() {
  final bytes = List<int>.generate(16, (_) => _random.nextInt(256));
  return bytes.map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();
}

/// The answer that was given to a request with an idempotency key.
class IdempotencyRecord {
  /// Creates a record.
  IdempotencyRecord({
    required this.key,
    required this.status,
    required this.body,
    Map<String, String>? headers,
    required this.createdAt,
  }) : headers = <String, String>{...?headers};

  /// The key of the request.
  final String key;

  /// The status of the answer.
  final int status;

  /// The body of the answer.
  final List<int> body;

  /// The headers of the answer.
  final Map<String, String> headers;

  /// When the answer was given.
  final DateTime createdAt;

  /// The record as a response.
  Response toResponse() => Response(
        status: status,
        headers: headers,
        body: body,
      );
}

/// The answers of the requests that carried an idempotency key.
///
/// The store lives in the memory of the process, so it protects a service
/// against the repeated calls of one caller. A service that has to survive a
/// restart keeps the records in its database instead.
class IdempotencyStore {
  /// Creates a store.
  ///
  /// The [ttl] is how long a record is kept and the [maxEntries] is how many
  /// records are kept at the same time.
  IdempotencyStore({
    this.ttl = const Duration(hours: 24),
    this.maxEntries = 10000,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  /// How long a record is kept.
  final Duration ttl;

  /// How many records are kept at the same time.
  final int maxEntries;

  final DateTime Function() _clock;
  final Map<String, IdempotencyRecord> _records = <String, IdempotencyRecord>{};

  /// How many records the store holds.
  int get length => _records.length;

  /// Finds the record of the request with the key [key].
  ///
  /// Returns `null` when the key is unknown or when its record is too old.
  IdempotencyRecord? find(String key) {
    _prune();
    return _records[key];
  }

  /// Keeps the [record] of a request.
  void remember(IdempotencyRecord record) {
    _prune();
    _records[record.key] = record;
    while (_records.length > maxEntries) {
      final oldest = _records.keys.first;
      _records.remove(oldest);
    }
  }

  /// Forgets the record of the request with the key [key].
  void forget(String key) => _records.remove(key);

  void _prune() {
    if (_records.isEmpty) {
      return;
    }
    final limit = _clock().subtract(ttl);
    _records.removeWhere((_, record) => record.createdAt.isBefore(limit));
  }
}

/// Answers a repeated request with the answer of the first one.
///
/// The middleware reads the `idempotency-key` header of the request. When the
/// key was already used, the answer of the first request is sent back and the
/// handler is not called again.
Middleware idempotencyMiddleware({IdempotencyStore? store}) {
  final records = store ?? IdempotencyStore();
  return (request, next) async {
    final key = request.header(idempotencyKeyHeader);
    if (key == null || key.isEmpty) {
      return next();
    }

    request.idempotencyKey = key;

    final record = records.find(key);
    if (record != null) {
      final response = record.toResponse();
      response.headers['idempotency-replayed'] = 'true';
      return response;
    }

    final response = await next();
    records.remember(
      IdempotencyRecord(
        key: key,
        status: response.status,
        body: response.body,
        headers: response.headers,
        createdAt: DateTime.now(),
      ),
    );
    return response;
  };
}
