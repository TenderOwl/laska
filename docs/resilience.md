# The resilience

Every microservice framework converges on the same list of primitives. Laska
ships it as one consistent set, and the way a service is called is written
**in the contract** — not in the configuration of every caller.

## The policy in the contract

```proto
service UsersService {
  option (laska.policy) = {
    timeout_ms: 2000
    max_attempts: 3
    backoff_ms: 100
    max_backoff_ms: 2000
    jitter: true
  };

  rpc GetUser(GetUserRequest) returns (User) {
    option (google.api.http) = { get: "/v1/users/{id}" };
    option (laska.policy) = { idempotent: true };
  }

  rpc CreateUser(CreateUserRequest) returns (User) {
    option (google.api.http) = { post: "/v1/users" body: "*" };
  }
}
```

The generator turns the policy into a class, and the generated client applies
it to every call:

```dart
UsersServicePolicies.getUser.timeout;           // 2s
UsersServicePolicies.getUser.retry.maxAttempts;  // 3
UsersServicePolicies.createUser.idempotent;     // false
```

The policy of the method wins over the policy of the service, and the caller
may still override it per call.

## What the runtime does

| Primitive | Behaviour |
|---|---|
| **Timeout** | Every attempt is timed out (2s by default). A call without a timeout is a bug. |
| **Retry** | An exponential backoff with jitter, capped by `max_backoff_ms`, honouring `Retry-After`. |
| **Idempotency** | A call that is not idempotent is never repeated; it carries an `idempotency-key` instead. |
| **Circuit breaker** | Closed → open → half-open. When the circuit is open the call fails fast with `503`. |
| **Bulkhead** | A limit of the calls that run at the same time, with a bounded queue. |

The breaker counts the **attempts**, not the calls: a dependency that fails
three times in a row opens the circuit, and the calls that follow are
answered with `503` right away instead of waiting for a timeout. That is the
difference between a failure and a pile-up.

## The dependency

The breaker and the bulkhead belong to the dependency, so they are configured
on the client:

```dart
final client = UsersServiceClient(
  baseUrl: 'http://localhost:8080',
  policy: const DependencyPolicy(
    circuitBreaker: CircuitBreakerPolicy(
      failureThreshold: 5,
      failureRatio: 0.5,
      minimumCalls: 10,
      cooldown: Duration(seconds: 5),
    ),
    bulkhead: BulkheadPolicy(maxConcurrent: 16, maxQueue: 32),
  ),
);
```

## The errors

One taxonomy, whatever transport the dependency speaks:

| Error | HTTP | gRPC |
|---|---|---|
| `DependencyFailure` | the status of the answer | the matching status |
| `DependencyTimeoutException` | `504` | `deadlineExceeded` |
| `CircuitOpenException` | `503` | `unavailable` |
| `BulkheadFullException` | `503` | `resourceExhausted` |

The generated client turns them into `LaskaApiException`, so the caller of the
client sees the status of the failure and not an exception of the framework.

## The idempotency

The server side replays the first answer of a key:

```dart
app.use(idempotencyMiddleware());
```

A repeated key answers with the first answer and the header
`idempotency-replayed: true`, so a client that repeats a call after a timeout
does not change anything twice.

## The discovery

The addresses of the services come from the environment:

```console
$ export LASKA_SERVICES="users=http://localhost:8080,orders=http://localhost:8081"
$ export USERS_URL=http://localhost:8080
```

```dart
final discovery = ServiceDiscovery.fromEnvironment();
final users = discovery.resolve('users');
```

`laska dev` sets the variable of every service of the workspace, so the
services find each other without a configuration. An unknown service is an
error, not a silent default.

## The outbox

The business row and the event are written in one transaction, and a
dispatcher publishes the pending events afterwards:

```dart
final outbox = await Outbox.ensureTable(database);
await database.transaction((transaction) async {
  await transaction.run('INSERT INTO orders (...) VALUES (...)', [...]);
  await outbox.enqueue(transaction, 'orders', 'OrderCreated', payload);
});
```

The delivery is at-least-once: an event that was published but not marked as
sent is published again, so the consumer has to be able to cope with a
repeated event.
