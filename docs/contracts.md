# The contracts

The contract is the product of Laska: one `.proto` file describes the
messages, the methods and the way the service is called, and everything else
is generated from it.

## The format

```proto
syntax = "proto3";

package users.v1;

// UsersService manages the accounts of the application.
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

  // CreateUser creates a new user. The call changes something, so it is
  // never retried.
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
```

The rules the contract follows are the ones `laska contract lint` checks:

- the package is versioned, e.g. `users.v1`, and it matches the name of the
  file;
- the messages, the enums and the services are written in PascalCase and the
  services end with `Service`;
- the fields are written in snake_case and the values of the enums in
  UPPER_SNAKE_CASE;
- the methods are written in PascalCase.

## The policy of the calls

`option (laska.policy)` describes **how the service is called**, on the
service or on a single method:

| Key | Meaning |
|---|---|
| `timeout_ms` | How long one attempt may take. |
| `max_attempts` | How many times the call is made, the first attempt included. |
| `backoff_ms` | The wait before the second attempt. |
| `max_backoff_ms` | The longest wait between two attempts. |
| `jitter` | Whether the wait is randomised. |
| `idempotent` | Whether the call may be repeated at all. |

The policy of the method wins over the policy of the service, and the policy
of the contract wins over the configuration of the caller — the way a service
is called is visible in the contract, not only in the code that calls it.

A call that is not idempotent is never retried, whatever the retry policy
says: repeating it could charge a customer twice. The generated client sends
an `idempotency-key` with such a call instead.

## Compile the contract

```console
$ dart run laska_cli:laska contract compile --proto api --out lib/generated
warning: Import "google/api/annotations.proto" of "users.proto" is recorded but not resolved.
generated: lib/generated/users.pb.dart
generated: lib/generated/openapi.json
```

There is no `protoc`, no plugin and no global installation: the contract is
parsed by a pure-Dart parser that ships with Laska. The command writes:

- the message classes with `fromJson`/`toJson` and `toProtoBytes`/`fromProtoBytes`;
- the service interface with one typed method per RPC;
- the REST projection of the methods, registered on the router;
- the typed client, with the policy of the contract applied;
- the OpenAPI 3.1 document.

The generated code is formatted with `package:dart_style`, which doubles as a
syntax check: a bug of the generator surfaces at compile time instead of in
the build of the service.

## Keep the contract compatible

```console
$ dart run laska_cli:laska contract diff --base contracts/v1 --candidate contracts/v2
BREAKING  users.v1.User.email: field was removed
1 breaking change(s), 0 non-breaking change(s).
```

The command exits with the code `1` when it finds a breaking change, so a
pipeline fails on it. The rules are the ones of Buf: a field that is removed,
a field number that is reused, a type that changes and a method that
disappears are breaking changes.

## Check the contract

```console
$ dart run laska_cli:laska contract lint --proto api
api/users.proto: users.v1.User.displayName: A field is written in snake_case.
1 problem(s) found.
```

The lint reads the contract the way a reviewer reads it: the naming, the
package layout and the version of the package. The command fails with the
code `1` when it finds a problem.

## The transports

The same contract speaks two transports:

| Transport | Format | Path |
|---|---|---|
| `HttpServiceTransport` | JSON | the REST projection, e.g. `/v1/users/u_1` |
| `GrpcServiceTransport` | binary protobuf | the RPC path, e.g. `/users.v1.UsersService/GetUser` |

```dart
final client = UsersServiceClient(
  baseUrl: 'http://localhost:8080',
  transport: GrpcServiceTransport(host: 'localhost', port: 50051),
);
```

The binary codec is pure Dart, so a contract keeps its wire format without
`protoc` on the machine of the service.
