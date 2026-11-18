# Getting started

## Scaffold a service

A service of Laska is a contract, an implementation and an entrypoint. The
command writes all of it, and the generated code is the code the contract
describes:

```console
$ dart run laska_cli:laska new service users
created: users/api/users.proto
created: users/lib/generated/users.pb.dart
created: users/lib/generated/openapi.json
created: users/lib/users_service.dart
created: users/bin/server.dart
created: users/test/users_service_test.dart
created: users/pubspec.yaml
created: laska.yaml
```

The service is added to the manifest of the workspace, so `laska dev` starts
it. A whole workspace with a first service is written with a name instead of
the word `service`:

```console
$ dart run laska_cli:laska new shop
created: shop/laska.yaml
created: shop/services/shop/api/shop.proto
...
```

> The packages of Laska are not published yet, so a project that is scaffolded
> from a checkout depends on the local workspace. The `--local` flag writes
> that dependency; without it the project depends on the published packages.

## Run the service

```console
$ cd users
$ dart pub get
$ dart run bin/server.dart
=> Laska listening on http://0.0.0.0:3789
```

The port of the service comes from the supervisor or from the manifest. The
`laska serve` command runs the service under the supervisor, which starts the
worker processes, restarts the ones that crash and stops them all on a
signal:

```console
$ dart run laska_cli:laska serve --entrypoint bin/server.dart --port 8080
```

## Call the service

The contract describes the REST projection, so the route is the one of the
contract:

```console
$ curl http://localhost:8080/v1/users/u_1
```

The typed client of the contract talks to the service with the policy of the
contract applied — the timeout, the retry and the idempotency key:

```dart
final client = UsersServiceClient(baseUrl: 'http://localhost:8080');
final user = await client.getUser(const GetUserRequest(id: 'u_1'));
```

## Run a workspace

The manifest of the workspace lists the services, the environment and the
dependencies between them:

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

`laska dev` starts every service, aggregates their logs into one stream and
sends their telemetry to a local collector, which prints the traces it
receives:

```console
$ dart run laska_cli:laska dev
=> collector on http://127.0.0.1:4318
=> users on http://127.0.0.1:8080
=> orders on http://127.0.0.1:8081
=> 2 service(s) started. Press Ctrl+C to stop.
[users 0] {"time":"...","level":"info","service":"users","message":"request",...}
collector: trace 4bf92f35 span 00f067aa http.server 12.4ms
```

The services are started in the order of their `depends_on`, and a service
waits for the services it depends on to answer before it is started. Every
service gets the address of the other services in its environment —
`USERS_URL`, `ORDERS_URL` — which is what the service discovery of the
runtime reads.

## Test the service

The harness runs the service in process, through the same dispatcher as the
HTTP server:

```dart
final client = testClient(app);

final response = await client.get('/v1/users/u_1');
response.expectStatus(404);
```

A test of a service never leaves data behind: `withTestDatabase` runs the body
of the test in a transaction that is rolled back afterwards.

```console
$ dart test
```

## What is next

- [The contracts](contracts.md) — the format, the policy of the calls and the
  checks of the contract.
- [The observability](observability.md) — the traces, the metrics and the
  probes.
- [The resilience](resilience.md) — the timeouts, the retries, the breaker and
  the idempotency.
- [The deployment](deployment.md) — the images, the manifests and the recipe
  of the continuous integration.
