/// The transactional outbox of a service.
///
/// The outbox solves the problem of two systems that have to change together:
/// the rows of the business and the message that tells another service about
/// them. The message is written in the same transaction as the rows, so the
/// message cannot get lost, and a background dispatcher publishes the
/// messages that were not published yet.
library;

import 'dart:async';
import 'dart:convert';

import '../db/database.dart';

/// A message of the outbox.
class OutboxMessage {
  /// Creates a message.
  OutboxMessage({
    required this.id,
    required this.topic,
    required this.payload,
    required this.createdAt,
    this.attempts = 0,
    this.lastError,
  });

  /// The id of the message.
  final String id;

  /// The topic of the message, e.g. `user.created`.
  final String topic;

  /// The body of the message.
  final String payload;

  /// When the message was written.
  final DateTime createdAt;

  /// How often the message was published without success.
  final int attempts;

  /// The error of the last attempt.
  final String? lastError;

  /// The body of the message as a JSON object.
  Map<String, dynamic> get payloadObject {
    final decoded = jsonDecode(payload);
    if (decoded is Map<String, dynamic>) {
      return decoded;
    }
    return const <String, dynamic>{};
  }
}

/// Publishes the messages of the outbox.
typedef OutboxPublisher = Future<void> Function(OutboxMessage message);

/// The outbox of a service.
class Outbox {
  /// Creates an outbox over the [database].
  Outbox(
    this.database, {
    this.table = 'outbox',
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  /// The database the messages are written to.
  final Database database;

  /// The table the messages are written to.
  final String table;

  final DateTime Function() _clock;

  /// Creates the table of the outbox, when it does not exist yet.
  Future<void> ensureTable() async {
    await database.execute('''
CREATE TABLE IF NOT EXISTS $table (
  id TEXT PRIMARY KEY,
  topic TEXT NOT NULL,
  payload TEXT NOT NULL,
  created_at TEXT NOT NULL,
  attempts INTEGER NOT NULL DEFAULT 0,
  sent_at TEXT,
  last_error TEXT
)''');
  }

  /// Writes a message in the outbox.
  ///
  /// The message is written in the transaction of [transaction], so it is
  /// published exactly when the rows of the business are committed.
  Future<String> enqueue(
    Database transaction, {
    required String topic,
    required Object payload,
    String? id,
  }) async {
    final messageId = id ?? _newId();
    await transaction.execute(
      'INSERT INTO $table (id, topic, payload, created_at, attempts) '
      'VALUES (?, ?, ?, ?, 0)',
      <Object?>[
        messageId,
        topic,
        jsonEncode(payload),
        _clock().toUtc().toIso8601String(),
      ],
    );
    return messageId;
  }

  /// The messages that were not published yet.
  Future<List<OutboxMessage>> pending({int limit = 50}) async {
    final rows = await database.query(
      'SELECT id, topic, payload, created_at, attempts, last_error '
      'FROM $table WHERE sent_at IS NULL ORDER BY created_at LIMIT ?',
      <Object?>[limit],
    );

    return rows.map((row) {
      return OutboxMessage(
        id: row['id']! as String,
        topic: row['topic']! as String,
        payload: row['payload']! as String,
        createdAt: DateTime.tryParse(row['created_at']! as String) ?? _clock(),
        attempts: (row['attempts'] as int?) ?? 0,
        lastError: row['last_error'] as String?,
      );
    }).toList();
  }

  /// Marks the message [id] as published.
  Future<void> markSent(String id) async {
    await database.execute(
      'UPDATE $table SET sent_at = ?, last_error = NULL WHERE id = ?',
      <Object?>[_clock().toUtc().toIso8601String(), id],
    );
  }

  /// Records that the message [id] could not be published.
  Future<void> markFailed(String id, Object error) async {
    await database.execute(
      'UPDATE $table SET attempts = attempts + 1, last_error = ? WHERE id = ?',
      <Object?>[error.toString(), id],
    );
  }

  /// How many messages were not published yet.
  Future<int> pendingCount() async {
    final rows = await database.query(
      'SELECT COUNT(*) AS total FROM $table WHERE sent_at IS NULL',
    );
    return (rows.first['total'] as int?) ?? 0;
  }

  String _newId() {
    final now = _clock().microsecondsSinceEpoch;
    return 'outbox_$now';
  }
}

/// Publishes the messages of an outbox in the background.
///
/// The delivery is at least once: a message that was published but not marked
/// as sent is published again, so the consumer has to be able to cope with a
/// repeated message.
class OutboxDispatcher {
  /// Creates a dispatcher for the [outbox], publishing with [publish].
  OutboxDispatcher({
    required this.outbox,
    required this.publish,
    this.interval = const Duration(seconds: 1),
    this.batchSize = 50,
  });

  /// The outbox the messages are read from.
  final Outbox outbox;

  /// Publishes one message.
  final OutboxPublisher publish;

  /// How long the dispatcher waits between two rounds.
  final Duration interval;

  /// How many messages are published in one round.
  final int batchSize;

  /// Publishes the pending messages until the dispatcher is stopped.
  ///
  /// The [stop] function is asked after every round, so a service can stop the
  /// dispatcher while it shuts down.
  Future<void> run({Future<bool> Function()? stop}) async {
    while (true) {
      await dispatchOnce();
      await Future<void>.delayed(interval);
      if (stop != null && await stop()) {
        return;
      }
    }
  }

  /// Publishes the pending messages of one round.
  ///
  /// Returns how many messages were published.
  Future<int> dispatchOnce() async {
    final messages = await outbox.pending(limit: batchSize);
    var published = 0;

    for (final message in messages) {
      try {
        await publish(message);
        await outbox.markSent(message.id);
        published++;
      } catch (error) {
        await outbox.markFailed(message.id, error);
      }
    }

    return published;
  }
}
