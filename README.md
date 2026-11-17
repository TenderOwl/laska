# Laska

**Laska is a contract-first service framework for [Dart](https://dart.dev/):** define the contract
once, get a typed server, typed clients for PHP/Python/Go/TS, traces, metrics and retries — and
ship it as a single binary.

- **Contracts**: one `.proto` file produces REST routes, gRPC endpoints, typed Dart and
  foreign-language clients, an OpenAPI 3.1 document, and a breaking-change check for CI.
- **Observability**: OpenTelemetry tracing, Prometheus metrics, correlated structured logs and
  `/healthz`/`/readyz` — built into the runtime, not bolted on.
- **Resilience**: timeouts, retries with jitter, circuit breaker, bulkhead and idempotency keys,
  with one consistent set of defaults across every service.
- **DX**: `laska new service`, `laska dev` for a whole multi-service workspace, `laska contract
  diff`, `laska migrate:run`.

The long-term design and the roadmap behind these points live in [PLAN.md](PLAN.md).

## Current state

Active development, **not for production use**. The core runtime, the contract pipeline and the
observability layer are implemented and working end to end (see below); resilience, the
multi-service workspace and the foreign-language SDKs are still to come.

| Package | What it holds |
|---|---|
| `packages/laska_core` | The runtime: routing, middleware, request/response, problem documents, config, logging, the supervisor, the data layer and the telemetry. |
| `packages/laska_contracts` | The contract pipeline: proto parser, code generator, OpenAPI export, breaking-change detection. |
| `packages/laska_cli` | The `laska` command line interface. |
| `packages/laska_test` | The test harness: an in-process HTTP client, expectation helpers, database helpers and a fake tracer. |
| `example/contract_slice` | A working vertical slice: contract → generated code → service → client. |

## Quick start

### 1. Write the contract

```proto
// api/users.proto
syntax = "proto3";

package users.v1;

// UsersService manages the accounts of the application.
service UsersService {
  // GetUser returns a single user by its identifier.
  rpc GetUser(GetUserRequest) returns (User) {
    option (google.api.http) = { get: "/v1/users/{id}" };
  }

  // CreateUser creates a new user.
  rpc CreateUser(CreateUserRequest) returns (User) {
    option (google.api.http) = { post: "/v1/users" body: "*" };
  }
}

message User {
  string id = 1;
  string email = 2;
  string display_name = 3;
  UserRole role = 4;
  repeated string tags = 5;
}

enum UserRole {
  USER_ROLE_UNSPECIFIED = 0;
  USER_ROLE_ADMIN = 1;
  USER_ROLE_MEMBER = 2;
}

message GetUserRequest { string id = 1; }
message CreateUserRequest { string email = 1; string display_name = 2; UserRole role = 3; }
```

### 2. Compile it

```console
$ dart run laska_cli:laska contract compile --proto api --out lib/generated
warning: Import "google/api/annotations.proto" of "users.proto" is recorded but not resolved.
generated: lib/generated/users.pb.dart
generated: lib/generated/openapi.json
```

No `protoc`, no plugins, no global installation: the contract is parsed by a pure-Dart parser
that ships with Laska.

### 3. Implement the service

The generated file holds the message classes, the service interface, the REST projection and a
typed client:

```dart
import 'package:laska_core/laska_core.dart';

import '../generated/users.pb.dart';

class UsersServiceImpl implements UsersService {
  @override
  Future<User> getUser(GetUserRequest request) async {
    final user = await _load(request.id);
    if (user == null) {
      throw HttpException(404, 'User "${request.id}" was not found');
    }
    return user;
  }
}
```

```dart
Future<void> main(List<String> arguments) async {
  final app = Laska();
  registerUsersService(app, UsersServiceImpl());

  await run(app, arguments: arguments, port: 8080);
}
```

The arguments of `main` are handed to `run()`, so the framework flags (`--laska-route-list`,
`--laska-migrate`) work no matter how the service is started.

### 4. Call it

The generated client is typed end to end:

```dart
final client = UsersServiceClient(baseUrl: 'http://127.0.0.1:8080');
final user = await client.getUser(const GetUserRequest(id: 'u_1'));

print(user.email); // ada@example.com
```

### 5. Keep the contract honest in CI

```console
$ dart run laska_cli:laska contract diff --base contracts/v1 --candidate contracts/v2
BREAKING  users.v1.User.email: field was removed
1 breaking change(s), 0 non-breaking change(s).
```

The command exits with code `1` when a breaking change is found, so a pipeline fails on it.

## Observability

One call wires the whole stack — request ids, tracing, metrics, the request log and the health
probes — into the service:

```dart
final app = Laska();

Observability.install(
  app,
  logger: Logger(service: 'users', version: '0.1.0'),
);

registerUsersService(app, UsersServiceImpl());

await run(app, arguments: arguments);
```

The service writes no instrumentation code:

- **Tracing** — every request gets a server span, every outgoing call a client span, every SQL
  statement a span. The trace continues across services: the generated client writes the
  `traceparent` header and the receiving service continues that trace, so a request through two
  services is one trace.
- **Metrics** — `/metrics` in the Prometheus text format, with the request count and the duration
  by route.
- **Probes** — `/healthz` (liveness) and `/readyz` (readiness, gated on the database).
- **Logs** — one JSON object per line, correlated with `request_id`, `trace_id` and `span_id`.
  `ctx.logger` carries the context of the request.

The tracer is an abstraction (`Tracer`), so the OpenTelemetry SDK can be replaced without touching
the runtime. The configuration uses the standard environment variables:

```console
$ export OTEL_SERVICE_NAME=users
$ export OTEL_EXPORTER_OTLP_ENDPOINT=http://localhost:4318
```

### The workspace runner

`laska dev` starts every service of the workspace, aggregates their logs in one stream and points
them at a local collector that prints the traces it receives:

```yaml
# laska.yaml
services:
  - name: users
    entrypoint: services/users/bin/server.dart
    port: 8080
  - name: orders
    entrypoint: services/orders/bin/server.dart
    port: 8081
```

```console
$ dart run laska_cli:laska dev
=> collector on http://127.0.0.1:4318
=> users on http://127.0.0.1:8080
=> orders on http://127.0.0.1:8081
=> 2 service(s) started. Press Ctrl+C to stop.
[users 0] {"time":"...","level":"info","service":"users","message":"request",...}
collector: trace 4bf92f35 span 00f067aa http.server 12.4ms
```

## The command line interface

```
laska contract compile   --proto <dir> --out <dir> [--title <t>] [--version <v>]
laska contract diff      --base <dir> --candidate <dir> [--quiet]
laska serve              [--entrypoint <file>] [--workers <n>] [--address <addr>] [--port <port>]
laska dev                [--manifest <file>] [--entrypoint <file>] [--collector-port <port>]
laska route:list         [--entrypoint <file>]
laska migrate:run        [--entrypoint <file>] [--directory <dir>]
```

`laska serve` runs the supervisor: it starts the worker processes of the service, shares the port
between them, restarts the ones that crash and stops them all on a signal. `laska route:list`
prints the route table of the service, and `laska migrate:run` applies the pending SQL migrations.

Every command has a help of its own. `laska --help` lists the commands, the global options and the
environment variables of the telemetry, and `laska help <command>` describes one command with its
options and its defaults:

```console
$ dart run laska_cli:laska help contract compile
laska contract compile — Generate the Dart code and the OpenAPI document of a contract.

Usage:
  laska contract compile [options]

Options:
  --proto <value>    Directory containing the .proto files.
                     (default: proto)
  --out <value>      Directory the generated code is written to.
                     (default: lib/generated)
  ...
```

> **Platform note.** On POSIX systems the workers share the port with SO_REUSEPORT and the kernel
> balances the connections between them. Windows has no such option: two processes cannot listen on
> the same port, so the supervisor runs a **single worker** there and says so in the log. The
> graceful stop is weaker on Windows as well, because a signal terminates the worker immediately
> instead of letting it drain.

## The runtime

The runtime is small on purpose and has no hidden magic:

```dart
final app = Laska();

app.alias('auth', (request, next) async {
  if (request.header('authorization') == null) {
    return Response.problem(401, 'Unauthorized', 'A token is required.');
  }
  return next();
});

app.group('/v1', (group) {
  group.get('/users/:id<int>', (ctx) => ctx.json(<String, Object?>{
        'id': ctx.params['id'],
      }), name: 'user.show', middleware: ['auth']);

  group.get('/users/:id?/files/*', (ctx) => ctx.text(ctx.params['*']!));
});
```

- **Routing** — static segments, `:param`, `:param<int>` (also `float`, `bool`, `uuid`, `slug` and
  custom regular expressions), optional `:param?` and the `*` wildcard. The priority is
  deterministic, and a path that exists with another method answers `405` with an `Allow` header.
- **Errors** — `HttpException(404, 'User was not found', code: 'user_not_found')` renders as an
  RFC 9457 `application/problem+json` document.
- **Middleware** — the order is global → group → route → handler, and a middleware may answer on
  its own instead of calling `next`. The global middleware runs for every route, even for the
  routes that were registered before it; the middleware of a group runs for the routes of that
  group only.
- **Config and logs** — `Config.string('PORT')` reads the environment first and the `.env` file
  second; `Logger` writes one JSON object per line and redacts the secrets.
- **Data** — `Database` over `package:postgres` and `package:sqlite3`, with SQL migrations applied
  by `laska migrate:run` and recorded in a `schema_migrations` ledger.

## Testing a service

The harness runs the service in process, through the same dispatcher as the HTTP server:

```dart
final client = testClient(app);

await client.get('/v1/users/42')
    .expectStatus(200)
    .expectJson(<String, Object?>{'id': '42'});
```

`withTestDatabase(database, (transaction) async { ... })` runs the body in a transaction that is
rolled back afterwards, so a test never leaves data behind.

## Running the checks

```console
$ dart pub get
$ dart run tool/check.dart
```

The script formats the repository, runs the analyzer and the tests of every package. The same
runs in CI via `.github/workflows/ci.yml`.

## The example

`example/contract_slice` is a complete vertical slice: a contract, the generated code, a service
implementation and an integration test that starts the server, calls it through the generated
client, checks the OpenAPI document and fails if the generated code is out of date.

## License

[MIT](https://github.com/amka/laska/blob/master/LICENSE)
