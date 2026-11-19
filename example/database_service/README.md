# The data layer of a service

A service that keeps its data in a database: the migrations of the schema, a
repository that owns the SQL, and a transfer that moves money without losing
any.

| Route | What it does |
|---|---|
| `GET /accounts` | Every account, in the order of its identifier. |
| `GET /accounts/:id` | One account, `404` when there is none. |
| `POST /accounts` | Creates an account. |
| `POST /transfers` | Moves money from one account to another. |
| `GET /transfers` | The ledger of the transfers. |

## Run it

```console
$ cd example/database_service
$ dart run lib/main.dart
```

```console
$ curl -s localhost:8080/accounts \
    -H 'content-type: application/json' \
    -d '{"id":"a_1","name":"Ada","balance":1000}'
```

## The migrations

The schema lives in plain `.sql` files under `migrations/`, named
`<version>_<name>.sql`. The file may hold a rollback after the marker
`-- @down`:

```sql
CREATE TABLE accounts (
  id TEXT PRIMARY KEY,
  name TEXT NOT NULL,
  balance INTEGER NOT NULL DEFAULT 0
);

-- @down
DROP TABLE accounts;
```

The migrations are applied in the order of their version and recorded in the
table `schema_migrations`, so a migration is never applied twice. The service
registers its database, so the flag `--laska-migrate` — and the command
`laska migrate:run` — apply them and stop:

```console
$ dart run lib/main.dart --laska-migrate
applied 2 migration(s)
  0001_create_accounts
  0002_create_transfers
```

## The repository

The repository is the only part of the service that knows the SQL. The routes
ask it for the accounts and never touch the database themselves:

```dart
final accounts = AccountRepository(database);

app.get('/accounts/:id', (ctx) async {
  final account = await accounts.findById(ctx.params['id']!);
  if (account == null) {
    throw HttpException(404, 'The account was not found.', code: 'account_not_found');
  }
  return ctx.json(account.toJson());
});
```

## The transaction

The money of a transfer moves in one transaction: the two balances and the
ledger are written together, and when any of the writes fails, the others are
rolled back. No money is created and none is lost.

```dart
await _database.transaction((transaction) async {
  await transaction.execute('UPDATE accounts SET balance = balance - ? WHERE id = ?', ...);
  await transaction.execute('UPDATE accounts SET balance = balance + ? WHERE id = ?', ...);
  await transaction.execute('INSERT INTO transfers (...) VALUES (...)', ...);
});
```

## The database of a service in production

The example uses SQLite, because it needs no server. A service in production
talks to PostgreSQL, and nothing else changes:

```dart
final database = await PostgresDatabase.fromEnvironment();
```

The readiness probe asks the database whether the service is able to serve
traffic, so a service with a broken database stops receiving traffic instead
of failing every request.

## The test

`test/database_test.dart` runs the service in process against a database in
the memory and checks the migrations, the repository and the transaction: a
transfer that fails changes neither the balances nor the ledger.
