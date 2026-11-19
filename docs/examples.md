# The examples

The examples of the repository are real services: they run, they answer, and
their tests check them. Every example is a package of the workspace, so the
script of the checks runs its tests with the tests of the framework:

```console
$ dart run tool/check.dart
```

| Example | What it shows |
|---|---|
| [contract_slice](../example/contract_slice) | The vertical slice: a contract, the generated code, the service and the client. |
| [auth_service](../example/auth_service) | The authentication of the callers: the tokens, the scopes, the API keys, the sessions and the limits. |
| [database_service](../example/database_service) | The data layer: the migrations, the repository, the transactions and the readiness of the service. |

## Run an example

Every example is a service of its own. It listens on the port 8080:

```console
$ cd example/auth_service
$ dart run lib/main.dart
```

```console
$ curl -s localhost:8080/me -H 'authorization: Bearer <token>'
```

The example of the contract needs the contract compiler, so the generated code
is checked in and the example runs without it.

## The vertical slice

`example/contract_slice` writes a contract, compiles it into the code of the
service and of the client, and calls the service through the generated client.
Its test starts the server, checks the OpenAPI document and fails if the
generated code is out of date — so the contract never drifts away from the
code.

The guide of the contracts is [contracts.md](contracts.md).

## The authentication of the callers

`example/auth_service` shows the four ways a caller may prove who it is: a
token, a scope of the token, the API key of a machine and the session of a
browser. The middleware of the routes is registered under a name, so a route
says what it needs:

```dart
app.alias('token', jwtMiddleware(keys.verifier));
app.alias('admin', requireScope('admin'));

app.get('/admin', (ctx) {
  return ctx.json(<String, Object?>{'message': 'Only an administrator sees this.'});
}, middleware: <Object>['token', 'admin']);
```

The refusal never says what is wrong with the secret of the caller: the answer
is a `401` or a `403` with a code, and the details stay inside the service.

The guide of the authentication is [auth.md](auth.md).

## The data layer of a service

`example/database_service` keeps its accounts in a database. The schema lives
in plain `.sql` files, the migrations are applied in the order of their
version and recorded in the table `schema_migrations`, and the SQL stays in
the repository:

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

The money of a transfer moves in one transaction, so the balances and the
ledger never disagree: when a write fails, the others are rolled back. The
service registers its database, so the readiness probe asks it whether the
service is able to serve traffic.
