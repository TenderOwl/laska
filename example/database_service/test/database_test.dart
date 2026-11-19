import 'package:database_service_example/app.dart';
import 'package:database_service_example/database.dart';
import 'package:laska_core/laska_core.dart';
import 'package:laska_test/laska_test.dart';
import 'package:test/test.dart';

void main() {
  group('the database of the service', () {
    late Database database;
    late TestClient client;

    setUp(() async {
      database = await openDatabase();
      client = testClient(await buildApp(database: database));
    });

    tearDown(() async {
      await database.close();
    });

    test('the migrations are applied', () async {
      final rows = await database.query(
        "SELECT name FROM sqlite_master WHERE type = 'table' AND name = 'accounts'",
      );

      expect(rows, hasLength(1));
    });

    test('the ledger of the migrations knows what was applied', () async {
      final rows = await database.query(
        'SELECT version FROM schema_migrations ORDER BY version',
      );

      expect(rows.map((row) => row['version']), <String>[
        '0001_create_accounts',
        '0002_create_transfers',
      ]);
    });

    test('the migrations are not applied twice', () async {
      final runner = MigrationRunner(database, directory: migrationsDirectory);
      final applied = await runner.migrate();

      expect(applied, isEmpty);
    });

    test('an account is created and found', () async {
      final created = await client.post(
        '/accounts',
        body: <String, Object?>{'id': 'a_1', 'name': 'Ada', 'balance': 1000},
      );

      created.expectStatus(201);
      expect(created.jsonObject['balance'], 1000);

      final found = await client.get('/accounts/a_1');
      found.expectStatus(200);
      expect(found.jsonObject['name'], 'Ada');
      expect(found.jsonObject['balance'], 1000);
    });

    test('a missing account is a 404', () async {
      final response = await client.get('/accounts/nope');

      response.expectStatus(404);
      expect(response.jsonObject['code'], 'account_not_found');
    });

    test('an account without a name is refused', () async {
      final response = await client.post(
        '/accounts',
        body: <String, Object?>{'id': 'a_1'},
      );

      response.expectStatus(400);
      expect(response.jsonObject['code'], 'invalid_account');
    });

    test('an account with a negative balance is refused', () async {
      final response = await client.post(
        '/accounts',
        body: <String, Object?>{'id': 'a_1', 'name': 'Ada', 'balance': -1},
      );

      response.expectStatus(400);
      expect(response.jsonObject['code'], 'invalid_balance');
    });

    test('the accounts are listed in the order of their identifier', () async {
      await _create(client, 'a_2', 'Grace');
      await _create(client, 'a_1', 'Ada');

      final response = await client.get('/accounts');

      response.expectStatus(200);
      final accounts = response.jsonObject['accounts']! as List<Object?>;
      expect(
        accounts.map((account) => (account! as Map<String, Object?>)['id']),
        <String>['a_1', 'a_2'],
      );
    });

    test('a transfer moves the money', () async {
      await _create(client, 'a_1', 'Ada', 1000);
      await _create(client, 'a_2', 'Grace');

      final transfer = await client.post(
        '/transfers',
        body: <String, Object?>{'from': 'a_1', 'to': 'a_2', 'amount': 250},
      );

      transfer.expectStatus(201);
      expect(transfer.jsonObject['amount'], 250);

      final source = await client.get('/accounts/a_1');
      expect(source.jsonObject['balance'], 750);

      final target = await client.get('/accounts/a_2');
      expect(target.jsonObject['balance'], 250);
    });

    test('the transfer is written in the ledger', () async {
      await _create(client, 'a_1', 'Ada', 1000);
      await _create(client, 'a_2', 'Grace');

      await client.post(
        '/transfers',
        body: <String, Object?>{'from': 'a_1', 'to': 'a_2', 'amount': 250},
      );

      final response = await client.get('/transfers');

      response.expectStatus(200);
      final transfers = response.jsonObject['transfers']! as List<Object?>;
      expect(transfers, hasLength(1));
      expect((transfers.single! as Map<String, Object?>)['amount'], 250);
    });

    test('a transfer that fails changes nothing', () async {
      await _create(client, 'a_1', 'Ada', 100);
      await _create(client, 'a_2', 'Grace');

      final transfer = await client.post(
        '/transfers',
        body: <String, Object?>{'from': 'a_1', 'to': 'a_2', 'amount': 250},
      );

      transfer.expectStatus(422);
      expect(transfer.jsonObject['code'], 'insufficient_funds');

      // The transaction was rolled back: the money of the account is the same
      // and the ledger holds nothing.
      final source = await client.get('/accounts/a_1');
      expect(source.jsonObject['balance'], 100);

      final ledger = await client.get('/transfers');
      expect(ledger.jsonObject['transfers'], isEmpty);
    });

    test('a transfer to a missing account changes nothing', () async {
      await _create(client, 'a_1', 'Ada', 1000);

      final transfer = await client.post(
        '/transfers',
        body: <String, Object?>{'from': 'a_1', 'to': 'nope', 'amount': 250},
      );

      transfer.expectStatus(404);
      expect(transfer.jsonObject['code'], 'account_not_found');

      final source = await client.get('/accounts/a_1');
      expect(source.jsonObject['balance'], 1000);
    });

    test('the readiness probe asks the database', () async {
      final ready = await client.get('/readyz');
      ready.expectStatus(200);

      await database.close();

      final broken = await client.get('/readyz');
      broken.expectStatus(503);
    });
  });
}

/// Creates an account through the service.
Future<void> _create(
  TestClient client,
  String id,
  String name, [
  int balance = 0,
]) async {
  final response = await client.post(
    '/accounts',
    body: <String, Object?>{'id': id, 'name': name, 'balance': balance},
  );
  response.expectStatus(201);
}
