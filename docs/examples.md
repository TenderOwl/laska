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
| [workspace](../example/workspace) | A workspace of two services: the service that keeps the records and the one that calls it. |

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

The example serves the contract on both transports: the REST projection on the
port 8080 and the methods of the contract on the port 50051. Its test calls the
service over HTTP and over gRPC and checks that the answers are the same.

The example holds the SDK of the contract in Go under `go/`: the messages of the
contract, the clients of its services and the runtime they need. Its tests run
the toolchain of Go — the codec of the wire, the messages and the client
against a server that speaks gRPC — and the test of the example starts the
service and calls it with the client of Go, so the two languages talk to each
other.

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

## A workspace of two services

`example/workspace` holds the two services and the manifest that ties them
together. Its files are exactly the files that `laska new shop` writes, so the
example is the proof that the command gives a project that runs.

```console
$ cd example/workspace
$ dart run laska_cli:laska dev
```

The command starts the services in the order of their dependencies: the gateway
waits for the service behind it to answer, and every service gets the address
of the others in its environment. The gateway calls the service behind it
through the client of its contract, so the call carries the policy of the
contract — the timeout, the retries, the circuit breaker — and the trace of the
request: the two services answer with one trace.

The test of the gateway starts both services and checks that the gateway answers
with the record of the service behind it, that a record that is not there is a
`404`, and that the two services belong to one trace.
