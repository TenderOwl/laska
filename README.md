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
- **Security**: JWT (HS/RS/ES), JWKS with the rotation of the keys, API keys, sessions with the
  defence against the fixation, and the rate limiting — with the same `401`/`403` everywhere.
- **DX**: `laska new service`, `laska dev` for a whole multi-service workspace, `laska contract
  diff`, `laska contract matrix`, `laska migrate:run`.

The long-term design and the roadmap behind these points live in [PLAN.md](PLAN.md), and the guides
live in [docs/](docs/README.md).

## Current state

Active development, **not for production use**. The core runtime, the contract pipeline, the
observability layer, the resilience layer, the workspace tooling and the release hardening are
implemented and working end to end (see below); the SDK of a contract in Go is written as well, and
the SDKs of PHP, Python and TypeScript are still to come. The packages of the framework are
published on pub.dev.

| Package | What it holds |
|---|---|
| `packages/laska_core` | The runtime: routing, middleware, request/response, problem documents, config, logging, the supervisor, the data layer and the telemetry. |
| `packages/laska_contracts` | The contract pipeline: proto parser, code generator, OpenAPI export, breaking-change detection. |
| `packages/laska_cli` | The `laska` command line interface. |
| `packages/laska_test` | The test harness: an in-process HTTP client, expectation helpers, database helpers, a fake tracer and a fake transport. |
| `example/contract_slice` | A working vertical slice: contract → generated code → service → client. |
| `example/auth_service` | The authentication of the callers: tokens, scopes, API keys, sessions and the limits. |
| `example/database_service` | The data layer of a service: migrations, a repository, transactions and the readiness. |
| `example/workspace` | A workspace of two services: the one that keeps the records and the one that calls it. |

## Installation

The command line interface comes from pub.dev and needs the Dart SDK:

```console
$ dart pub global activate laska_cli
$ laska --help
```

Without the Dart SDK, the [release](https://github.com/tenderowl/laska/releases)
holds a bundle for every platform and the installer puts it in place. The
installer checks the SHA-256 of the bundle before it unpacks it:

```console
$ curl -fsSL https://raw.githubusercontent.com/tenderowl/laska/main/tool/install.sh | sh
```

```powershell
> irm https://raw.githubusercontent.com/tenderowl/laska/main/tool/install.ps1 | iex
```

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

The contract is not only a service of Dart: `laska contract sdk --lang=go` writes the SDK of the
contract in Go — the messages, the clients of the services and the runtime they need — and the SDK
talks to the service over gRPC:

```go
client, err := users.NewUsersServiceClient("localhost:50051")
user, err := client.GetUser(ctx, &users.GetUserRequest{Id: "u_1"})

print(user.Email) // ada@example.com
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

## Resilience

The way a service is called is written **in the contract**, not in the configuration of every
caller:

```proto
service UsersService {
  // The policy of the calls to the service.
  option (laska.policy) = {
    timeout_ms: 2000
    max_attempts: 3
    backoff_ms: 100
    max_backoff_ms: 2000
    jitter: true
  };

  // GetUser returns a single user by its identifier.
  rpc GetUser(GetUserRequest) returns (User) {
    option (google.api.http) = { get: "/v1/users/{id}" };
    option (laska.policy) = { idempotent: true };
  }

  // CreateUser creates a new user: the call changes something, so it is never retried.
  rpc CreateUser(CreateUserRequest) returns (User) {
    option (google.api.http) = { post: "/v1/users" body: "*" };
  }
}
```

The generator turns the policy into a class, and the generated client applies it to every call:

```dart
UsersServicePolicies.getUser.timeout;           // 2s
UsersServicePolicies.getUser.retry.maxAttempts;  // 3
UsersServicePolicies.createUser.idempotent;     // false
```

What the runtime does with it:

- **Timeout** on every attempt (2s by default) — a call without a timeout is a bug.
- **Retry** with an exponential backoff and jitter, honouring `Retry-After`. Only the idempotent
  calls are repeated: a call that changes something is never retried, and the generated client
  sends an `idempotency-key` with it instead.
- **Circuit breaker** per dependency: closed → open → half-open. When the circuit is open the call
  fails fast with `503` instead of waiting for a timeout, so a failing dependency does not pile up.
- **Bulkhead** per dependency: a concurrency limit, so one slow dependency cannot exhaust the
  process.
- **One error taxonomy**: `DependencyFailure`, `DependencyTimeoutException`, `CircuitOpenException`
  and `BulkheadFullException` map to one HTTP status and one gRPC status, whatever transport the
  dependency speaks.

The breaker and the bulkhead belong to the dependency, so they are configured on the client:

```dart
final client = UsersServiceClient(
  baseUrl: 'http://127.0.0.1:8080',
  policy: const DependencyPolicy(
    circuitBreaker: CircuitBreakerPolicy(failureThreshold: 5),
    bulkhead: BulkheadPolicy(maxConcurrent: 16),
  ),
);
```

The same contract speaks two transports: `HttpServiceTransport` (JSON over the REST projection)
and `GrpcServiceTransport` (binary protobuf over the RPC path). The outbox writes the business row
and the event in one transaction and publishes them afterwards, and the discovery resolves the
address of a dependency from `LASKA_SERVICES` or `<NAME>_URL`.

### The workspace runner

`laska dev` starts every service of the workspace, aggregates their logs in one stream and points
them at a local collector that prints the traces it receives:

```yaml
# laska.yaml
environment:
  LOG_LEVEL: debug

services:
  - name: users
    entrypoint: services/users/bin/server.dart
    port: 8080
  - name: orders
    entrypoint: services/orders/bin/server.dart
    port: 8081
    depends_on: [users]
    environment:
      DATABASE_URL: postgres://localhost/orders
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

The services are started in the order of their `depends_on`, and a service waits for the services it
depends on to answer before it is started (`--startup-timeout` says how long it waits). Every
service gets the address of the other services in its environment — `USERS_URL`, `ORDERS_URL` —
which is exactly what the service discovery of the runtime reads:

```dart
final discovery = ServiceDiscovery.fromEnvironment();
final users = discovery.resolve('users'); // http://127.0.0.1:8080
```

## The command line interface

```
laska new <name>          # scaffold a workspace with two services
laska new service <name>  # scaffold a service inside a workspace
laska contract compile   --proto <dir> --out <dir> [--title <t>] [--version <v>]
laska contract diff      --base <dir> --candidate <dir> [--quiet]
laska contract lint      --proto <dir>
laska contract matrix    [--dir <dir>] [--version <dir>] [--out <file>] [--details]
laska keys generate      --alg <alg> --out <dir> [--kid <kid>] [--bits <n>]
laska upgrade            [--api <name> --from <v> --to <v>] [--path <dir>] [--dry-run]
laska serve              [--entrypoint <file>] [--workers <n>] [--address <addr>] [--port <port>]
laska dev                [--manifest <file>] [--entrypoint <file>] [--collector-port <port>]
laska route:list         [--entrypoint <file>]
laska migrate:run        [--entrypoint <file>] [--directory <dir>]
laska deploy:dockerfile  [--manifest <file>] [--out <dir>] [--image <repo>]
laska deploy:k8s         [--manifest <file>] [--out <dir>] [--namespace <ns>]
laska ci:recipe          [--out <file>] [--proto <dir>] [--base <dir>] [--candidate <dir>] [--matrix <dir>]
```

`laska serve` runs the supervisor: it starts the worker processes of the service, shares the port
between them, restarts the ones that crash and stops them all on a signal. `laska route:list`
prints the route table of the service, and `laska migrate:run` applies the pending SQL migrations.

`laska new service` writes a service that runs: the contract, the generated code, the
implementation, the entrypoint and a test, and it adds the service to the manifest of the
workspace. `laska new <name>` writes a whole workspace with two services: the first one keeps the
records and the second one calls it through the typed client of its contract, so the project shows
the whole path of the framework. `laska deploy:dockerfile` and `laska deploy:k8s` write the images
and the manifests of the cluster from that manifest, and `laska ci:recipe` writes the workflow of
the pipeline.

`laska contract matrix` compares every version of a contract with every other one and tells which
client works against which server. `laska keys generate` writes the keys that sign the tokens of the
service — the private key in a file of its own, the public key set next to it — and `laska upgrade`
moves a service to a new version of the framework or of its own API.

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
- **Files and HTML** — `app.staticFiles('/assets', 'web/assets')` serves the files of a directory
  with the content type of their extension, with the validators of the cache (`ETag`,
  `Last-Modified`, `304`) and without a path that leaves the directory; `ctx.html(...)` answers
  with a document of HTML. The runtime builds nothing and renders nothing — the application writes
  the HTML and the frontend is built by the toolchain of the application. See
  [the guide of the files](docs/static-files.md).

## Authentication

The three ways a service is called in practice are middleware of the runtime:

```dart
final verifier = JwtVerifier(keys: <JwtKey>[key]);

app.use(jwtMiddleware(verifier));          // Authorization: Bearer <token>
app.use(apiKeyMiddleware(guard));          // x-api-key: <key>
app.use(sessionMiddleware(store));         // Cookie: laska_session=<id>
app.use(rateLimitMiddleware(limiter));     // 429 and a retry-after
```

The caller lands in `ctx.request.principal`, so a handler never reads the headers itself. The
runtime does not trust the header of a token: the algorithm of the token has to be the algorithm of
the key that signed it, so `alg: none` and the confusion of the algorithms are refused. The keys of
the service are published as a JWKS, and the cache of the key set refreshes it when a token names a
key it does not know — never more than once every ten seconds, so a flood of made-up `kid`s cannot
turn the service into a client of itself.

`laska keys generate` writes the keys of the service: the private key in a file of its own and the
public key set next to it.

The id of a session is regenerated when the privileges of the session change, so an id that leaked
before the login is dead afterwards.

See [the guide of the authentication](docs/auth.md).

## The versions of a contract

A contract that breaks its consumers goes to the next major version of its API, and the diff says so
in the pipeline:

```console
$ dart run laska_cli:laska contract diff --base contracts/v1 --candidate contracts/v2
BREAKING  users.v1.User.email: field was removed
```

When a contract has more than two versions, the matrix compares every version with every other one
and tells which client works against which server:

```console
$ dart run laska_cli:laska contract matrix --dir contracts
client \ server  v1      v2
v1               yes     yes*
v2               yes*    yes
```

`laska upgrade --api users --from v1 --to v2` moves the contract, the generated code and the calls
of the service to the new version together.

See [the guide of the versions](docs/versioning.md) and [the guide of the matrix](docs/compatibility.md).

## The performance of the hot path

The tables of the router are built when a route is registered, the chain of the middleware of a route
is built once and kept, and the body of a request is read into a buffer that comes from a pool. The
budget of the hot path is a number of objects per request, and the tests hold the runtime to it.

```console
$ dart run tool/benchmark.dart
router: a static route                  0.09 us/op     11363636 op/s
dispatch: a static route                3.72 us/op      268504 op/s
```

See [the guide of the performance](docs/performance.md).

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

A generated client is exercised without a network too: `TestTransport` answers with what the test
prepared and records the requests it received, so the retries, the breaker and the bulkhead of the
client are covered by a unit test.

```dart
final transport = TestTransport()..alwaysRespond(TransportResponse(statusCode: 503));

final client = UsersServiceClient(
  baseUrl: 'http://127.0.0.1:8080',
  transport: transport,
);

await expectLater(client.getUser(const GetUserRequest(id: 'u_1')), throwsA(isA<LaskaApiException>()));
expect(transport.callCount, 3); // the call was retried twice
```

## Running the checks

```console
$ dart pub get
$ dart run tool/check.dart
```

The script formats the repository, runs the analyzer and the tests of every package. The same
runs in CI via `.github/workflows/ci.yml`.

## The examples

`example/contract_slice` is a complete vertical slice: a contract, the generated code, a service
implementation and an integration test that starts the server, calls it through the generated
client, checks the OpenAPI document and fails if the generated code is out of date.

`example/auth_service` shows how a caller proves who it is — with a token, a scope of the token,
the API key of a machine or the session of a browser — and what the service answers when the
proof is missing.

`example/database_service` shows the data layer of a service: the migrations of the schema in
plain SQL, a repository that owns the queries, and a transfer that moves money in one
transaction, so the balances and the ledger never disagree.

`example/workspace` holds the two services and the manifest that ties them together — the files
are exactly the files that `laska new shop` writes. The second service calls the first one
through the client of its contract, so the call carries the policy of the contract and the trace
of the request: the two services answer with one trace.

The guide of the examples is [docs/examples.md](docs/examples.md).

## License

[MIT](https://github.com/amka/laska/blob/master/LICENSE)
