import 'dart:convert';

import 'package:laska_core/laska_core.dart';
import 'package:test/test.dart';

void main() {
  late SqliteDatabase database;
  late Outbox outbox;

  setUp(() async {
    database = SqliteDatabase.memory();
    outbox = Outbox(database);
    await outbox.ensureTable();
  });

  tearDown(() async {
    await database.close();
  });

  test('writes a message in the transaction of the business', () async {
    await database.transaction((transaction) async {
      await transaction.execute(
        'CREATE TABLE users (id TEXT PRIMARY KEY, email TEXT NOT NULL)',
      );
      await transaction.execute(
        "INSERT INTO users (id, email) VALUES ('u_1', 'a@example.com')",
      );
      await outbox.enqueue(
        transaction,
        topic: 'user.created',
        payload: <String, dynamic>{'id': 'u_1'},
      );
    });

    final pending = await outbox.pending();

    expect(pending, hasLength(1));
    expect(pending.single.topic, 'user.created');
    expect(pending.single.payloadObject, <String, dynamic>{'id': 'u_1'});
    expect(pending.single.attempts, 0);
  });

  test('keeps no message when the transaction fails', () async {
    await expectLater(
      database.transaction((transaction) async {
        await outbox.enqueue(
          transaction,
          topic: 'user.created',
          payload: <String, dynamic>{'id': 'u_1'},
        );
        throw StateError('the business failed');
      }),
      throwsA(isA<DatabaseException>()),
    );

    expect(await outbox.pendingCount(), 0);
  });

  test('publishes the pending messages and marks them as sent', () async {
    await outbox.enqueue(
      database,
      topic: 'user.created',
      payload: <String, dynamic>{'id': 'u_1'},
    );

    final published = <OutboxMessage>[];
    final dispatcher = OutboxDispatcher(
      outbox: outbox,
      publish: (message) async => published.add(message),
    );

    expect(await dispatcher.dispatchOnce(), 1);
    expect(published, hasLength(1));
    expect(published.single.topic, 'user.created');
    expect(await outbox.pendingCount(), 0);
  });

  test('keeps a message that could not be published', () async {
    await outbox.enqueue(
      database,
      topic: 'user.created',
      payload: <String, dynamic>{'id': 'u_1'},
    );

    final dispatcher = OutboxDispatcher(
      outbox: outbox,
      publish: (message) async => throw StateError('the broker is down'),
    );

    expect(await dispatcher.dispatchOnce(), 0);
    expect(await outbox.pendingCount(), 1);

    final pending = await outbox.pending();
    expect(pending.single.attempts, 1);
    expect(pending.single.lastError, contains('the broker is down'));
  });

  test('publishes the payload of the message as it was written', () async {
    await outbox.enqueue(
      database,
      topic: 'user.created',
      payload: <String, dynamic>{'id': 'u_1', 'email': 'a@example.com'},
    );

    final pending = await outbox.pending();

    expect(
      jsonDecode(pending.single.payload),
      <String, dynamic>{'id': 'u_1', 'email': 'a@example.com'},
    );
  });
}
