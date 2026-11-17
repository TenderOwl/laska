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

Active development, **not for production use**. The contract pipeline is implemented and working
end to end (see below); observability, resilience and the multi-service workspace are still to
come.

| Package | What it holds |
|---|---|
| `packages/laska_core` | The runtime: routing, middleware, request/response, problem documents. |
| `packages/laska_contracts` | The contract pipeline: proto parser, code generator, OpenAPI export, breaking-change detection. |
| `packages/laska_cli` | The `laska` command line interface. |
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
Future<void> main() async {
  final app = Laska();
  registerUsersService(app, UsersServiceImpl());

  await run(app, port: 8080);
}
```

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

## The command line interface

```
laska contract compile   --proto <dir> --out <dir> [--title <t>] [--version <v>]
laska contract diff      --base <dir> --candidate <dir> [--quiet]
```

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
