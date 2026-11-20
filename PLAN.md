# Laska — Product & Architecture Plan

> **Laska is a contract-first service framework for Dart.**
> One contract → typed server stubs + typed clients in any language, observability and
> resilience built in, one binary to deploy.

**Status (2026-11-17):** Phase 1 (core runtime), Phase 2 (contract pipeline), Phase 3
(observability), Phase 4 (inter-service calls and resilience) and Phase 5 (workspace and CLI
maturity) are implemented. The runtime has a
router with parameter constraints and named routes, an explicit middleware chain, RFC 9457 error
rendering, config + structured logging, a graceful shutdown with a worker supervisor, a thin `Db`
layer with SQL migrations and a test harness that exercises a service in process. The contract
pipeline ships with a **pure-Dart `.proto` parser** instead of `protoc`, which removes the native
toolchain from the critical path entirely (§4.3). The observability layer traces a request through
the services it touches, exports Prometheus metrics and serves the health probes, with one call to
install it. The resilience layer gives every outgoing call a timeout, a retry with jitter, a circuit
breaker, a bulkhead and an idempotency key — and the policy of the call is written **in the
contract**, so the way a service is called is visible to everyone who reads it (§4.12). The
workspace layer scaffolds a service from a contract, runs a whole workspace with one command and
writes the images, the manifests and the recipe of the pipeline (§5.5). The runtime also serves the
files of a directory and answers with HTML, so a service may carry the frontend of a workspace
(§4.14). See §6 for what is done and what is left.

---

## 0. Positioning

### 0.1 The one-liner

**Laska — the Go-style service framework for Dart teams: define the contract once, get a
typed server, typed clients for PHP/Python/Go/TS, traces, metrics, and retries — without
assembling five tools in every repository.**

### 0.2 Who it is for

Not "Dart developers who want a web framework". The primary user is a **team that writes
services in PHP, Python or Go today and wants one more service in a language that is
fast to write and cheap to run**. The secondary user is a Dart team that has outgrown
`shelf` and does not want to assemble `dart_frog` + `package:postgres` + `dartastic_opentelemetry`
+ a queue + a CLI by hand.

That second audience is the reason the framework is *polyglot-first*: the contract, not the
language, is the unit of reuse.

### 0.3 What Laska is — and what it is deliberately not

| Laska **is** | Laska **is not** |
|---|---|
| A service framework: contract → server + clients | A Django replacement (admin panel, templates, ORM with relations) |
| Opinionated about the *operational* surface | Opinionated about the *data* surface (SQL stays yours) |
| Polyglot: clients for Go/PHP/Python/TS from the same contract | A Dart-only ecosystem |
| Observability, resilience and multi-service DX as first-class features | A benchmark-first "fastest HTTP server" |
| One binary, one CLI, no runtime dependencies | A monolith framework with a plugin for everything |

**Why not "the Django of Dart":** Django's moat is batteries — ORM, migrations, admin,
templates, auth. That market is contested: Serverpod (4.1.0) already ships ORM, migrations,
auth, cache, WebSocket streaming, a testing framework, a first-party web server (Relic) and
Docker/Terraform, with 5000+ tests behind it. Beating a funded team at "batteries" is a
multi-year fight on their home turf. The whitespace is not "more batteries" — it is
**contract-first operations for polyglot teams**, which nobody in Dart occupies and which
matches the author's actual working context (CTO of companies running PHP/Python/Go
services).

**Why not "faster than Rust":** performance claims do not survive contact with different
workloads, and they age badly. The defensible claim is **time-to-first-correct-service** and
**operational surface area**: how long from an empty repo to a service that is deployed,
traced, retried and observable.

---

## 1. Where Laska came from

Audit of the original tree (`lib/` was ~700 lines of real code, last commit 2024-08-01). The legacy
prototype has since been removed (`git rm`, history preserved); this section records why each
decision was taken, because the current code is a rewrite of it.

### Keep

| Asset | Why it survives |
|---|---|
| Trie/static-map routing idea (`router.dart`) | The static-route hashmap fast path and the segment trie are sound; the *matcher* needs replacing, not the concept. |
| Echo-style middleware signature | `Middleware`/`next` chaining is the right shape, just needs a cleaner contract. |
| `dart:io` `HttpServer` + `shared: true` port sharing | Viable for multi-process workers; keep the technique. |
| `basic_auth.dart` | Replaced by the real auth package, but the middleware shape carries over. |
| `http_body.dart` multipart parser | The logic is a fork of the Dart team's old `http_parser`. **Take the maintained upstream package instead of forking it.** |

### Rewrite

| Asset | Problem |
|---|---|
| `router.dart` | No route groups, no param constraints (`:id<int>`), no optional segments, no named routes, no route-model binding. `lookup()` ignores HTTP method, so 405 detection happens late and inconsistently. |
| Middleware application (`server.dart:_applyMiddlewares`) | Middlewares live in a `Set` and are applied in two separate passes (route-then-global). Ordering is incidental, not specified. |
| `Context` | A thin `HttpRequest` wrapper. `param()` reads back into the matched route, so it is unusable outside a route match. No typed request/response contract. |
| Handler typing | Everything is `Function`. Handler signatures are unchecked at compile time — the single biggest DX loss. |
| `Configuration` | Mutable public fields, no env loading, no validation, no typed config. |
| `Laska` app object | Sends the whole app across an isolate boundary and mutates public fields (`config`, `router` setters). Needs an explicit lifecycle. |

### Drop

| Asset | Reason |
|---|---|
| **Multi-isolate worker model** | The blocking problem. Dart isolates share **no mutable state**, so a DB pool, session store, cache client or job queue cannot be shared across workers — each isolate would get its own copy, and per-request DI singletons are impossible. Replaced by *one isolate per process, many processes* (see §4.1). |
| `event` package lifecycle events | `Event`/`EventArgs` is a weak substitute for a real lifecycle hook system. Replaced by explicit `onStart`/`onShutdown` hooks. |
| Vendored `http_body.dart` | Use `package:http_parser`. |
| `Set<Middleware>` in `Configuration` | Ordering must be explicit, so use `List`. |

### Missing entirely — *as of the legacy prototype; most of it is implemented now*

DI container · request validation · config/env loading · structured logging · graceful shutdown ·
contract tooling (protobuf compilation, codegen, breaking-change detection) · OpenAPI export ·
distributed tracing · metrics · health/readiness probes · inter-service clients · resilience
primitives (retry, circuit breaker, bulkhead, idempotency) · workspace/multi-service tooling ·
SQL migrations · auth (JWT / session / API key) · rate limiting · CLI · test harness.

**Test coverage then:** the router only. Nothing exercised the server, the middleware chain,
error paths, or the isolate model.

**Test coverage now:** 380 tests across five packages — the router, the dispatcher, the middleware
chain, the config and the logger, the server and its graceful drain, the supervisor with real
worker processes, the database layer and the migration runner, the tracing and the metrics, the
OpenTelemetry adapter, the health probes, the resilience core (the retry, the breaker, the
bulkhead, the idempotency, the discovery and the outbox), the protobuf codec, the HTTP and the
gRPC transports, the contract linter, the scaffolder, the test harness and the CLI.

---

## 2. Design principles

1. **The contract is the product.** The framework's job is to turn one contract file into a
   server, a client, and documentation that cannot drift apart. Everything else is support.
2. **Generated, not handwritten.** Users should write plain Dart (handlers, domain logic).
   Boring, mechanical, error-prone code — proto messages, service stubs, client calls,
   registration, DI wiring, OpenAPI, breaking-change reports — is generated.
3. **Typed at the boundary.** Dart has no runtime reflection, so anything needing type info is
   resolved at **compile time** (codegen), never at runtime.
4. **Opinionated about operations, neutral about data.** Traces, metrics, health probes,
   timeouts, retries and error envelopes are decided by the framework. SQL, schema and query
   style are decided by the service.
5. **One runtime, many processes.** Never multi-isolate a single app in one process.
6. **Pluggable at the seams, opinionated in the middle.** Trace exporter, metrics backend,
   auth guard, cache store, queue backend and contract compiler are all interfaces with a
   default implementation.
7. **The framework owns the boring parts; the service owns the domain.** Handlers are thin.
8. **Zero native dependencies.** The delivered artifact is a single self-contained AOT binary.
   No toolchain, no `protoc` on the user's PATH, no libc surprises.

---

## 3. Package layout

Pub workspace monorepo (Dart 3.6+ workspaces; SDK 3.14 is available locally).

```
laska/                    # the umbrella of the repository — the root of the workspace
├── packages/
│   ├── laska_core/        # app, router, request/response, middleware, config, logger,
│   │                      # errors, supervisor, telemetry, resilience, SQL migrations
│   ├── laska_contracts/   # contract compilation, codegen, client generation, diffing, OpenAPI
│   ├── laska_cli/         # the `laska` CLI
│   └── laska_test/        # test harness: in-process client, expectations, database helpers
├── example/
│   └── contract_slice/    # the vertical slice: contract → generated code → service → client
├── docs/                  # the guides: getting started, contracts, observability, resilience, deployment
└── tool/                  # repo-level checks
```

**Deliberately smaller than the previous plan (11 → 5).** Telemetry and resilience live inside
`laska_core` until they prove they need their own release cadence; they are the kind of
feature that gets adopted only if it is one import away. `laska_contracts` is separate because
its dependency surface (codegen, protoc, buf) differs from the runtime and would otherwise
weigh down every service that only wants to serve HTTP.

All packages version in lockstep, and the gate of the repository checks it: a
version that drifts between the packages of the workspace breaks the
publication, so `tool/check.dart` refuses it. The root of the repository is the
umbrella `laska` — it re-exports the runtime — but a workspace root cannot be
published, so a service depends on `laska_core`, and on `laska_contracts` for
the codegen.

---

## 4. Architecture decisions

### 4.1 Runtime model — one isolate per process, many processes

```
                    ┌─────────────────────────────┐
   traffic ────────▶│ supervisor (laska serve)    │
                    │  spawn N worker processes   │
                    └──────┬───────────┬──────────┘
                           │           │
                    ┌──────▼───┐  ┌────▼─────┐
                    │ worker 1 │  │ worker 2 │   1 isolate each
                    │ 1 thread │  │ 1 thread │   shared DB pool, sessions, cache
                    └──────────┘  └──────────┘
                           │           │
                    ┌──────▼──────────▼──────────┐
                    │ PostgreSQL · Redis · storage │
                    └─────────────────────────────┘
```

- Each worker is a separate OS process running **one** Dart isolate → in-process state (DB pool,
  session store, cache, in-flight rate-limit counters) is coherent within a worker.
- Workers bind the same port via `HttpServer.bind(..., shared: true)` (SO_REUSEPORT where the OS
  supports it).
- Worker count defaults to `min(cores, 8)`, overridable by `--workers` / `LASKA_WORKERS`.
- Health: supervisor restarts crashed workers, drains on SIGTERM (graceful shutdown: stop accepting,
  finish in-flight requests within a timeout, flush queues, close pools).
- **Every app must be safe to run as N processes.** No in-process global state as a source of truth.

**Platform notes.** On POSIX systems `shared: true` is SO_REUSEPORT and the kernel balances the
connections between the workers. **Windows has no SO_REUSEPORT**: two processes cannot listen on
the same port, so the supervisor runs a single worker there and says so in the log. The graceful
stop is also weaker there, because `Process.kill` terminates the worker immediately instead of
delivering SIGTERM. A worker that keeps crashing is abandoned after `maxRestarts` tries, so a
misconfigured service fails visibly instead of looping forever.

*Consequence to document loudly:* this replaces the old isolate model, so `Laska` objects are no
longer shipped across isolates — a worker gets its own app instance built in-process.

### 4.2 Contract model — protobuf first, HTTP annotations

The contract format is **protobuf**. One `.proto` file describes messages and services; REST
routes are derived from the same file via `google.api.http` annotations.

```
api/users/v1/users.proto
──────────────────────────────────────────────────────────
syntax = "proto3";
package users.v1;

message GetUserRequest { string id = 1; }
message User { string id = 1; string email = 2; }

service UsersService {
  rpc GetUser(GetUserRequest) returns (User) {
    option (google.api.http) = { get: "/v1/users/{id}" };
  }
}
```

From this single file Laska produces:

| Artifact | Consumer | Status |
|---|---|---|
| Dart message classes with `fromJson`/`toJson` | service + clients | done |
| Server interface + typed handler signatures | the service author | done |
| Route table (REST, from `google.api.http`) | HTTP clients, gateways, browsers | done |
| Typed Dart client (timeouts, error mapping) | the service author and other services | done |
| Typed Dart client with the policy of the contract (timeout, retry, idempotency) | the service author and other services | done |
| OpenAPI 3.1 document | docs, client generators, gateway | done |
| Breaking-change report (`laska contract diff`) | CI | done |
| Binary protobuf codec (pure Dart) | wire compatibility with other languages | done |
| gRPC client transport for the same contract | other services | done |
| gRPC service descriptor + server stub | other services | done |
| PHP/Python/Go/TS client SDKs | consumers in other languages | planned |

**Wire format of the slice:** the generated messages follow the protobuf JSON mapping
(field names in lowerCamelCase, enums by their proto name), and the REST projection speaks
JSON. The binary protobuf codec and the gRPC client transport are Phase 4 work — they are done:
every message has `toProtoBytes()`/`fromProtoBytes()`, and the same generated client talks HTTP
with JSON or gRPC with protobuf, chosen by the transport it is given. The gRPC *server* side is
done as well: the runtime serves the methods of the contract under the name of the contract, so
one registration of the service answers on both transports. The foreign-language SDKs are what
is left.


**Why protobuf and not OpenAPI-first:** protobuf is the only contract format with a mature
cross-language toolchain (protoc plugins for Go, PHP, Python, Java, C#, TypeScript), with a
stable wire format, and with existing semantic conventions for breaking-change detection
(Buf's rules). OpenAPI stays in the picture as an *output* — generated from the same contract —
so REST consumers and documentation are never a second source of truth.

**Why not OpenAPI-first:** it would mean shipping and maintaining a second schema language, and
OpenAPI's request/response modelling is weaker for streaming and internal RPC.

### 4.3 Contract compilation — no toolchain on the user's machine

**Implemented:** Laska parses `.proto` files itself, in pure Dart (`laska_contracts`
contains a hand-written proto3 parser). There is no `protoc`, no plugin binary and no
global installation: `laska contract compile` works on a machine that only has the Dart
SDK.

- The parser covers the subset Laska needs: `syntax`, `package`, `import` (which
  are resolved), messages with scalar/message/enum/repeated/optional fields, `map` fields, groups of
  a `oneof`, messages and enums declared inside a message, enums, services and
  `google.api.http` bindings including `additional_bindings` and `body`.
- The types that are written without a qualifier are resolved the way protobuf resolves them:
  the scope of the message is searched first, then the scopes the message is declared in, and
  the files the file imports.
- The well-known types of protobuf (`google.protobuf.Timestamp`, `Duration`, `Any` and `Empty`) are
  types a contract may use. They live in the runtime and not in the generated code, so every
  service of a contract speaks of them with the same Dart types.
- Constructs outside that subset (`proto2`, the extensions) raise a
  `ProtoParseException` with a file and a line — they are never silently ignored.
- Generated code is formatted with `package:dart_style`, which doubles as a syntax check:
  a generator bug surfaces at compile time instead of in the consumer's build.
- The contract is validated before generation: unknown types, duplicate Dart class names,
  duplicate field numbers, path parameters that are not fields of the request message and
  unknown request/response types are hard errors.

**Why this is better than the original plan:** the plan assumed `protoc` plus
`protoc_plugin`, which meant a native toolchain on every developer's machine — exactly the
tax the framework promises to remove. A hand-written parser is more work up front and
strictly less friction afterwards.

**Still to come:** proto2 syntax and the extensions. (`bytes` fields are
supported since Phase 4.) When the subset outgrows the parser, `protoc` stays available as a
cross-check in CI — the generated model is the same either way.


### 4.4 Code generation — what Laska generates vs. what the user writes

Laska's generator (`laska contract generate`, or a `build_runner` builder for those who prefer it)
produces:

- `*.pb.dart` — messages and service descriptors (`protoc_plugin`).
- `*_service.dart` — an abstract class per service, with one typed method per RPC.
- `*_routes.dart` — route registration for the REST projection, wired into the router.
- `*_client.dart` — a typed client with per-method timeout/retry defaults.
- `*_openapi.json` — the OpenAPI 3.1 document.

The user writes:

- the implementation of the generated service interface,
- the domain logic,
- the transport-agnostic part of the handler (no `HttpRequest`, no JSON maps).

The contract is the only place where the API shape is declared. Adding a field to a message and
regenerating updates server, clients and docs in one step.

### 4.5 Contract diffing — breaking-change detection in CI

`laska contract diff --base <dir> --candidate <dir>` compares two contract snapshots and fails on
breaking changes, using Buf's semantic rules (field number reuse, type change, removal of a
field, changing a required method, and so on). The command exits with code `1` when it finds a
breaking change, so a CI job fails on it.

This is a small feature with a disproportionate effect on the target audience: it turns
"the mobile team got a surprise on release day" into "the CI pipeline stopped the merge". It is
also the feature that makes Laska relevant to a PHP/Python/Go org even for services written in
other languages: **a Dart service can own the contract and enforce it for everyone.**

### 4.6 HTTP layer — native `dart:io`, no `shelf`

Use `dart:io` `HttpServer` directly with a hand-rolled pipeline.

- **Why not shelf:** we need raw control over streaming responses (SSE), WebSocket upgrades,
  streaming multipart uploads straight to disk, request body limits, and graceful drain.
  Shelf's `Request` abstraction forces awkward workarounds for upgrades and streaming uploads.
- **Why not a bare-metal framework (shelf_router / dart_frog / Serverpod):** we want our own
  opinionated DX, and none of them give us the Adonis-style controller + validator + ORM combination.
- The `Request`/`Response` types we expose are **ours** (`laska_core`), shaped like AdonisJS:
  `ctx.request.body()`, `ctx.params`, `ctx.query`, `ctx.session`, `ctx.auth`.
- `package:http_parser` provides multipart parsing (replaces the vendored `http_body.dart`).
- WebSocket upgrade is intercepted in the dart:io entry point *before* the pipeline.

### 4.7 Router — segment matcher with constraints and groups

Rewrite `router.dart` around a segment tree with deterministic priority.

| Syntax | Meaning |
|---|---|
| `/users` | static segment |
| `/users/:id` | named parameter |
| `/users/:id<int>` | parameter with a constraint (`int`, `float`, `bool`, `uuid`, `slug`) |
| `/users/:code<^[A-Z]{3}$>` | parameter with a custom regular expression, anchored to the whole value |
| `/users/:id?` | optional trailing parameter |
| `/files/*` | wildcard (rest of path) |
| `ANY` | any HTTP method |

Features:

- **Route groups** with prefix + middleware + scope: `app.group('/admin', (group) {...})`.
- **Named routes** and a URL generator: `app.urlFor('users.show', {'id': '1'})` → `/v1/users/1`.
- **405 with an `Allow` header** — the matcher knows which methods exist for a path.
- **Deterministic priority**: static > constrained parameter > parameter > wildcard. No
  "last registered wins" ambiguity.
- **Contract-driven routes** — routes generated from `google.api.http` annotations are registered
  through the same matcher, so hand-written and generated routes coexist with one priority model.
- Keep the static-route hashmap fast path from the current implementation.
- `laska route:list` prints the full route table (method, path, name, middleware).

### 4.8 Middleware — explicit, ordered, onion model

```dart
typedef Next = Future<void> Function();
abstract class Middleware {
  Future<void> handle(Request ctx, Next next);
}
```

- Order is **global → group → route → handler**, and it is *specified*, not incidental.
- The chain is resolved **when the request arrives**, not when the route is registered: the global
  middleware runs for every route — including the routes registered before it — and the middleware
  of a group runs for the routes of that group only.
- Named/aliased middleware: `app.alias('auth', authMiddleware)`, then
  `app.get('/me', h, middleware: ['auth'])`. A route may also take a middleware instance directly.
- A middleware short-circuits by returning a response of its own instead of calling `next`
  (replaces the current "return null" convention, which is easy to get wrong).
- The middleware chain is the **single instrumentation point**: tracing, metrics, logging and
  request-id propagation are implemented as built-in middleware, not as user-installed packages.
  This is why observability is cheap to adopt and impossible to retrofit later without breaking
  the API.
- The built-in set: `requestIdMiddleware`, `loggingMiddleware`, `corsMiddleware`,
  `securityHeadersMiddleware`.

### 4.9 Dependency injection — explicit registration, optional codegen

Dart has no runtime reflection, so constructor injection cannot be resolved at runtime.

- **Default (v1):** explicit registration — `app.singleton(UserRepo.new)`, `app.bind(() => UserController(repo))`.
  AOT-safe, zero build step, fully explicit.
- **Generated (v1):** the contract generator emits a wiring module for the generated service
  implementations, so a service with ten RPCs does not require ten manual registrations.
- **Optional (v1.1):** a `build_runner` builder that reads `@injectable` annotations. Users who
  want it opt in; the explicit API stays supported.

### 4.10 Error handling — one error model across HTTP and RPC

- `HttpException(status, message, {code, details})` → rendered as **RFC 9457 `application/problem+json`**
  by default, with per-field details for validation errors.
- The same error object maps to a **gRPC status code** when the request arrives over gRPC
  (`NOT_FOUND` → 404, `INVALID_ARGUMENT` → 422, and so on). One error taxonomy, two transports.
- Every response carries a request id; errors are logged with a stack trace and the request id.
- A pluggable `ExceptionHandler` registry (like Adonis `report()`/`render()`), so users can add
  Sentry/etc. later.

### 4.11 Observability — built in, not bolted on

The whole observability stack is one contract: **OTel in, Prometheus out, logs correlated.**

- **Tracing**: `laska_core` owns a `Tracer` abstraction; the OpenTelemetry SDK
  (`dartastic_opentelemetry`, Apache-2.0) is the default implementation behind it, so the SDK can
  be swapped when the official Dart OTel SDK lands. Traces, metrics and logs with OTLP/gRPC and
  OTLP/HTTP exporters.
- **Auto-instrumentation**: the framework creates spans for inbound requests, outbound service
  calls, SQL queries (via the `TracingDatabase` wrapper) and queue jobs. Users get a useful trace
  without writing a single span.
- **Logs**: structured JSON with `trace_id`, `span_id`, `service`, `version` and `request_id`
  on every line, so `laska dev` and any log aggregator can join them. `ctx.logger` carries the
  context of the request.
- **Metrics**: `/metrics` in Prometheus text format — request count/latency by route, error rate,
  dependency call latency, pool saturation.
- **Probes**: `/healthz` (liveness) and `/readyz` (readiness, gated on DB/queue state).
- **Configuration**: standard `OTEL_*` environment variables, so an existing OTel collector
  works with no Laska-specific setup.

**Why this is a differentiator:** Dart is still the last top-15 language without an officially
maintained OTel SDK. A framework that ships OTel as a first-class, opinionated part of the
runtime turns a gap in the ecosystem into the framework's reason to exist.

**The cost of the choice:** `laska_core` now depends on the OpenTelemetry SDK, which pulls in
`grpc` and `protobuf`. The runtime stays pure Dart — no native toolchain — but the dependency
tree of every service grew. If the SDK weight turns out to matter, the abstraction is the seam:
the implementation moves to its own package without a change in the API.

### 4.12 Inter-service calls and resilience

Every microservice framework eventually converges on the same list. Laska ships it as one
consistent, configurable set rather than as a pile of third-party packages.

- **Typed clients**: generated client per contract, with per-method timeout and retry defaults.
- **Timeouts**: mandatory, with a sane default (2s) — a call without a timeout is a bug.
- **Retry**: exponential backoff with jitter, only for idempotent methods, honouring
  `Retry-After`; disabled by default for non-idempotent RPCs unless marked as such in the contract.
- **Circuit breaker**: closed → open → half-open, with configurable failure ratio and cooldown.
- **Bulkhead**: per-dependency concurrency limit, so one slow dependency cannot exhaust the process.
- **Idempotency keys**: propagated end-to-end and honoured by the service handler.
- **Outbox helper**: write business rows and an outbox row in one transaction; a background
  dispatcher publishes and marks them sent (at-least-once delivery, no distributed transactions).
- **Service discovery**: static configuration (env / `laska.yaml`) first — Consul/Kubernetes
  discovery is a later plug, not a v1 dependency.
- **Error mapping**: gRPC status ↔ HTTP status ↔ `ProblemDetail` in one place.

**Implemented (Phase 4).** The whole set lives in `laska_core/src/resilience/` and is applied by
the generated client without a line of user code:

- `DependencyPolicy` holds the timeout, the retry, the circuit breaker, the bulkhead and the
  idempotency of a call. `Dependency` is the one place where they meet: it runs the bulkhead, the
  breaker, the per-attempt timeout and the retry loop, and it traces the call as one client span
  with the number of the attempts.
- **The policy is in the contract.** A service declares how it wants to be called with
  `option (laska.policy) = { timeout_ms, max_attempts, backoff_ms, max_backoff_ms, jitter,
  idempotent }`, on the service or on a single method. The generator turns it into a
  `<Service>Policies` class, so the retry policy is visible in the contract instead of in the
  configuration of the caller.
- **Retries only for idempotent calls.** A call that changes something is never repeated, whatever
  the retry policy says; the generated client adds an `idempotency-key` header to it.
- **The breaker counts the attempts**, not the calls: a dependency that fails three times in a row
  opens the circuit, and the calls that follow fail fast with `503` instead of piling up. The
  timeout of the dependency is what turns the failure into an answer; a caller that waits for a
  timeout instead of a breaker gets a pile-up.
- **The same contract over two transports**: `HttpServiceTransport` speaks JSON over the REST
  projection, `GrpcServiceTransport` speaks the binary protobuf over the RPC path. The generated
  client works with both, and `TestTransport` (in `laska_test`) lets a test exercise it without a
  network.
- **One error taxonomy**: `DependencyFailure`, `DependencyTimeoutException`, `CircuitOpenException`
  and `BulkheadFullException` map to one HTTP status (`httpStatusOfError`) and one gRPC status, so
  a service degrades the same way whatever transport the dependency speaks.
- **The outbox** writes the event and the business row in one transaction; the dispatcher publishes
  the pending events and marks them sent — at-least-once delivery without a distributed
  transaction.
- **Static discovery**: `LASKA_SERVICES="users=http://localhost:8080"` or `USERS_URL` resolves the
  address of a dependency; an unknown service is an error, not a silent default.

### 4.13 Data access — SQL stays yours

Microservices own their schema. A framework-level ORM with relations, eager loading and a
migration-diff engine is a large product with a poor fit for that model, and it would put Laska
head-to-head with Serverpod's ORM and with `ormed`/`dart-orm`, which are already converging on a
good design.

Instead:

- `package:postgres` (v3) and `package:sqlite3` are used directly, with a thin `Db` helper
  (pool, health check, transaction helper, typed row mapping).
- **SQL-first migrations**: numbered, reviewable `.sql` files applied by `laska migrate:run`,
  with a `schema_migrations` ledger and rollback support. No auto-migration in production, ever.
- Generated contract types double as the API layer's DTOs; the database layer is separate and
  explicit.
- Optional adapters for `ormed` / `dart-orm` / `drift` may be published later as separate
  packages — **not** built in core, and **not** built by Laska.

The honest trade: a service author writes a few more lines of SQL than they would with an ORM,
and gains an ORM-independent schema, no codegen step, and no framework lock-in on the data layer.

### 4.14 The frontend of a workspace — the files and the HTML, nothing more

A workspace does not hold only APIs: a service may carry the frontend of the workspace — a landing
page, an admin panel — and the frontend calls the other services over their contracts. Such a
service is the third kind of a participant of the workspace, next to the `service` and the
`gateway`.

The runtime serves the files of a directory and answers with HTML:

- `app.staticFiles(prefix, directory)` mounts a directory under a prefix. The file is served with
  the content type of its extension, with the validators of the cache (`ETag`, `Last-Modified` and a
  `304` without a body) and with `X-Content-Type-Options: nosniff`. The path of the request is
  decoded by the runtime, and a path that points outside of the directory is refused.
- `ctx.html(...)` and `Response.html(...)` answer with a document of HTML.

The boundary is drawn on purpose:

- **Laska does not render the templates.** The HTML of an answer is written by the application; a
  service that needs templates picks a library for them.
- **Laska does not build the frontend.** The bundler of the application builds it, and the runtime
  serves the result.
- **Laska does not hold the state of the browser.** The state of the caller lives in the services
  of the workspace, and the frontend holds the token of it.

So Laska is not a "mini-Django": it does not become the framework of the frontend, it stays the
runtime of the service that carries the frontend. The whole of the track is three steps: the
runtime (done), the headers of a call in the generated client (so the frontend passes the token of
the session), and the scaffold `laska new app` with the kind `app` in the manifest of the
workspace.

---

## 5. Feature specs

### 5.1 `laska_core`

*Done:*

- `Laska` app object: route verbs, `group`, `use`, `alias`, `urlFor`, `database`,
  `migrationsDirectory`, `dispatcher`.
- `Request` — method, path, `uri`, headers, `query`, `params`, `body`, `json()`, `id`.
- `Response` — `json`, `text`, `html`, `bytes`, `problem` (RFC 9457), `copyWith`.
- `Context` — request + app + `params`, `query`, `headers`, `json`, `text`, `html`.
- `StaticFiles` — the files of a directory: `app.staticFiles(prefix, directory)`, the content types
  by the extension, the validators of the cache (`ETag`, `Last-Modified`, `304`) and the safe path
  that does not leave the directory.
- `Dispatcher` — the single place where routing, the middleware chain and the error rendering meet;
  used by the server and by the test harness alike.
- `Config` — environment over `.env`, typed accessors (`string`, `integer`, `number`, `boolean`,
  `list`, `secret`), secret redaction.
- `Logger` — structured JSON output, levels, secret redaction, `service`/`version` fields.
- Middleware: explicit order, named aliases, and the built-in set (request id, request logging,
  CORS, security headers).
- `LaskaServer` — `dart:io` server with an in-flight drain and a graceful `stop()`.
- `Supervisor` — worker processes on a shared port, restart of crashed workers, graceful stop.
- `Database` over `package:postgres` and `package:sqlite3`, plus the SQL migration runner.
- Telemetry: the `Tracer` abstraction with the OpenTelemetry implementation, the `Meter` with a
  Prometheus exposition, `TracingDatabase`, the tracing and the metrics middleware, the health
  probes and `Observability.install(app)`.
- Resilience: `DependencyPolicy`, `Dependency`, `CircuitBreaker`, `Bulkhead`, the idempotency
  store and its middleware, the static `ServiceDiscovery`, the `Outbox` and its dispatcher, and
  the error taxonomy with the HTTP ↔ gRPC status mapping.
- Transports: `ServiceTransport` with the HTTP (JSON) and the gRPC (protobuf) implementations,
  the pure-Dart protobuf codec (`ProtoWriter`/`ProtoReader`) and the `Request.idempotencyKey`.

*Planned:*

- `singleton`/`bind` DI, lifecycle hooks (`onStart`/`onReady`/`onShutdown`), auth (JWT, session
  cookies, API keys), rate limiting, streaming responses, WebSocket upgrades, `package:http_parser`
  for multipart uploads.

### 5.2 `laska_contracts`

- Contract compilation with a managed, cached `protoc`.
- Dart codegen: messages, service interfaces, REST route registration, typed clients, DI wiring.
- Foreign-language SDK generation by orchestrating upstream protoc plugins
  (`--lang=go`, `--lang=php`, `--lang=python`, `--lang=ts`).
- OpenAPI 3.1 export from the same contract, served at `/api-docs` in dev and exportable as a
  static file in CI.
- `laska contract diff` — breaking-change detection with Buf-compatible semantics. [done]
- `laska contract lint` — naming, field-naming and package-layout rules, in CI. [done]

### 5.3 `laska_cli`

```
laska new <name>          # scaffold a project                               [done]
laska new service <name>  # scaffold a service inside a workspace             [done]
laska serve [--workers=N] # run the HTTP server (supervisor)          [done]
laska dev                 # run all services of a workspace + local infra + aggregated logs
laska contract compile    # compile contracts, generate code         [done]
laska contract generate --lang=go
laska contract diff --base <dir> --candidate <dir>                   [done]
laska contract lint --proto <dir>                                     [done]
laska route:list          # dump the route table                      [done]
laska migrate:make <name> # scaffold a SQL migration
laska migrate:run|status|rollback                                     [run done]
laska db:seed
laska build               # AOT compile
laska deploy:dockerfile   # the images of the services of the workspace     [done]
laska deploy:k8s          # the manifests of the services of the workspace  [done]
laska ci:recipe           # the recipe of the continuous integration        [done]
```

Built on `package:args`. `laska serve` is the supervisor described in §4.1. `laska dev` is the
single most valuable command for the target audience: it starts every service in the workspace,
wires them to a local Postgres/Redis (via a generated compose file), aggregates their logs, and
shows live traces — the "one command instead of five tools" promise in practice.

`laska new` writes a service that runs: the contract, the generated code, the implementation, the
entrypoint and a test, and it adds the service to the manifest of the workspace. `laska deploy:*`
writes the images and the manifests of the cluster from that manifest, and `laska ci:recipe` writes
the workflow of the pipeline, so the artefacts of a project are never written by hand.

Every command has a help: `laska --help` lists the commands, the global options and the
environment variables of the telemetry, `laska help <command>` describes one command with its
options and its defaults, and `--help` works on every command. The help is rendered from the
parser itself, so it cannot drift away from the commands that are actually there. An unknown
command is reported and exits with the code `64`.

### 5.4 `laska_test`

*Done:*

- `testClient(app)` → an in-process client that goes through the same dispatcher as the HTTP
  server, with `expectStatus`/`expectJson`/`expectHeader`/`expectBodyContains`.
- `openTestDatabase()` — an in-memory SQLite database for fast unit tests.
- `withTestDatabase(database, body)` — the body runs in a transaction that is rolled back
  afterwards, so a test never leaves data behind.
- `TestTransport` — a transport that answers from the test: it records the requests and returns
  the answers the test prepared, so a generated client can be exercised (retries, breaker,
  bulkhead) without a network.

*Planned:*

- Fixtures/seed helpers, fake cache/session/queue/telemetry.
- Contract test helpers: assert that the implementation matches the generated service interface,
  and golden-file tests for the OpenAPI document.

---

## 6. Milestones

Assume one developer at ~20 h/week. Sizes are rough.

### Phase 0 — Groundwork (3–5 days) — *mostly done*

- [x] Restructure into a pub workspace; the legacy `lib/` moved out and then removed with `git rm`
      (history preserved).
- [x] CI: `dart analyze`, `dart format --set-exit-if-changed`, `dart test` via `tool/check.dart`.
- [x] Commit/branch/lint policy; `CONTRIBUTING.md`; changelog process.
- [x] Publish skeleton packages to pub.dev.

**Done when:** `laska serve` boots an empty app; CI green on all three OSes — **done**. The runtime
and the CLI work, the four packages of the workspace are published on pub.dev (`0.1.0` and later), and the CI
matrix runs on Linux, macOS and Windows.

### Phase 1 — Core runtime (12–18 days) — **done**

- [x] `Request` / `Response` / `Context` over `dart:io`.
- [x] Router: static segments, `:param`, `*` wildcard, static fast path, groups with prefix
      and middleware, 405 + `Allow` header.
- [x] Middleware pipeline with explicit ordering (global → group → route → handler).
- [x] `HttpException` + RFC 9457 `application/problem+json` rendering.
- [x] Parameter constraints (`:id<int>`, `:id<uuid>`, `:id<slug>`, custom regex), optional
      segments, named routes, `urlFor`, `route:list`.
- [x] Middleware aliases (`app.alias('auth', mw)`), the built-in middleware set (request id,
      logging, CORS, security headers), request ids.
- [x] Config (`.env` + environment, environment wins), structured logging with redaction.
- [x] Graceful shutdown with in-flight drain, supervisor (`laska serve`), worker crash-restart.
- [x] `Db` helper over `package:postgres` / `package:sqlite3` + SQL migration runner.
- [x] `laska_test` harness with the in-process HTTP client and the database helpers.

**Done when:** a route with a param constraint, a group with middleware, and a JSON 422 all behave
as specified, with tests — **done**. The behaviour is pinned by 102 tests in
`packages/laska_core/test`, 15 in `packages/laska_test/test` and 8 CLI tests.


### Phase 2 — Contracts & codegen (15–20 days) — *differentiator* — **done (vertical slice)**

- [x] Pure-Dart proto3 parser — no `protoc`, no native toolchain (§4.3).
- [x] Contract validation: unknown types, duplicate names, duplicate field numbers, path
      parameters that are not request fields, unknown request/response types.
- [x] Dart codegen: message classes with `fromJson`/`toJson`, service interface, REST route
      registration, typed client with timeouts and error mapping.
- [x] `google.api.http` annotations → routes, including `additional_bindings` and `body`.
- [x] OpenAPI 3.1 export + `/api-docs` serving helper.
- [x] `laska contract diff` with Buf-compatible breaking-change rules.
- [x] Generated code formatted with `package:dart_style` (also a syntax check).
- [x] Drift check: the example fails if the checked-in generated code is out of date.
- [x] Foreign-language client generation: `laska contract sdk --lang=go` writes the SDK of
      a contract in Go — the messages of the contract, the clients of its services and the
      runtime they need. The SDK is a module of its own, it depends on nothing but the
      standard library of Go, and it talks to a service over gRPC. PHP, Python and
      TypeScript are next.
- [x] Binary protobuf codec and the gRPC transport (client side — done in Phase 4).
- [x] The gRPC server: the runtime serves the methods of a contract, and the generated code
      registers the service of a contract over gRPC next to its REST projection.

**Done when:** one `.proto` produces a working REST endpoint, a gRPC endpoint, a Dart client, an
OpenAPI document and a CI check that fails on a breaking change — **done**; the SDK of the contract
in Go is done as well, and the SDKs of PHP, Python and TypeScript are what is left.


### Phase 3 — Observability (10–14 days) — **done**

- [x] `Tracer` abstraction inside `laska_core`; the OpenTelemetry SDK
      (`dartastic_opentelemetry`) is the default implementation behind it, so it can be replaced.
- [x] `OTEL_*` environment configuration: `OTEL_SERVICE_NAME`,
      `OTEL_EXPORTER_OTLP_ENDPOINT`, `OTEL_TRACES_SAMPLER_ARG`, `OTEL_SDK_DISABLED`.
- [x] Auto-instrumentation: a server span per request, a client span per outgoing call
      (the generated client writes the `traceparent` header), a span per SQL statement
      (`TracingDatabase`). The spans of the queue jobs come with the queue backend of Phase 4.
- [x] Structured logs correlated by `trace_id`/`span_id`/`request_id` — `ctx.logger` carries
      the context of the request.
- [x] Prometheus `/metrics`, `/healthz` and `/readyz`.
- [x] `laska dev` — the workspace runner with aggregated logs and a local collector that
      prints the traces it receives.

**Done when:** a request through two services shows up as one trace, with metrics and correlated
logs, with no instrumentation code written by the user — **done**. The behaviour is pinned by the
integration test `example/contract_slice/test/observability_test.dart`: the client span and the
server span of a call share the trace id, because the generated client writes the `traceparent`
header and the server continues that trace.

### Phase 4 — Inter-service & resilience (12–16 days) — **done**

- [x] Generated client with per-method timeout/retry defaults.
- [x] Retry with backoff + jitter, idempotency-key propagation.
- [x] Circuit breaker, bulkhead, graceful degradation.
- [x] Outbox helper (transactional publish).
- [x] Service discovery via static config; gRPC + HTTP transports for the same contract.

**Done when:** a dependency failure produces a circuit-open response in 5 seconds instead of a
pile-up, and the retry policy is visible in the contract — **done**. The first half is pinned by
`example/contract_slice/test/client_resilience_test.dart`: the dependency answers `503`, the
breaker opens after the attempts of the first call, and the next call is answered with `503` in
under a second instead of waiting for the timeout — the whole scenario stays below the 5 seconds of
the gate. The second half is pinned by the contract itself: `option (laska.policy)` declares the
timeout, the number of the attempts, the backoff, the jitter and the idempotency, and the
generator turns it into the `<Service>Policies` class the client uses.

### Phase 5 — Workspace & CLI maturity (10–14 days) — **done**

- [x] `laska.yaml` workspace manifest, multi-service `laska dev`.
- [x] `laska new service`, scaffolding from a contract template.
- [x] Dockerfile + Kubernetes manifest generation.
- [x] CI recipes: `analyze`, `test`, `contract diff`, `contract lint`.
- [x] Docs: getting started, contracts, observability, resilience, deployment.

**Done when:** a two-service workspace runs from `laska dev` on a fresh machine with one command —
**done**. The manifest holds the services, the environment and the dependencies between them;
`laska dev` starts the services in the order of their dependencies, waits for a dependency to
answer before it starts the service that needs it, and gives every service the address of the
other ones (`USERS_URL`), which is what the discovery of the runtime reads. The services come from
`laska new service`, which writes the contract, the generated code, the implementation, the
entrypoint and a test — a scaffolded service passes `dart analyze` and `dart test` as it is. The
images, the Kubernetes manifests and the recipe of the pipeline are written from the same
manifest. The documentation lives in `docs/`.

### Phase 6 — Release hardening (8–12 days) → **v1.0**

- [x] Auth hardening: key rotation, JWKS support, session fixation defence, rate limiting.
- [x] Semver policy, upgrade guide, `laska upgrade` codemods.
- [x] Contract compatibility matrix, end-to-end example service published.
- [x] Performance pass on the hot path (buffer reuse, precomputed route tables, allocation budget).

**Done when:** `laska new` produces a two-service workspace with contracts, generated clients,
tracing, resilience and passing tests — this is **v1.0**.

The phase is implemented in seven steps, each of them closed by the full validation of the
repository (`dart format .` and `dart run tool/check.dart`):

| Step | What it holds |
|---|---|
| 6.1 | The tokens (`HS`, `RS`, `ES`), the API keys, the principal and the middleware of the authentication. |
| 6.2 | The JWKS, the rotation of the keys and `laska keys generate`. |
| 6.3 | The sessions, the defence against the fixation of a session, and the rate limiting. |
| 6.4 | The policy of the versions, the guide of the upgrade and `laska upgrade`. |
| 6.5 | The matrix of the compatibility and the two-service workspace of `laska new`. |
| 6.6 | The performance of the hot path: the tables of the router, the reuse of the buffers, the budget of the allocations and the benchmark. |
| 6.7 | The guides, the plan, the readme and the changelog of the release. |

The guides of the phase live in `docs/`: `auth.md`, `versioning.md`, `upgrading.md`,
`compatibility.md` and `performance.md`.

### The distribution of v0.2.0

The tag `v0.2.0` runs `.github/workflows/release.yml`: the bundle of the command
line interface is built for Linux, macOS and Windows, on x64 and on arm64, and the
archives are attached to the release of the repository with their checksums. The
release `v0.2.0` is published, and the installers `tool/install.sh` and
`tool/install.ps1` fetch the bundle of the platform and check its checksum before
they unpack it.

The packages of the workspace are published on pub.dev as `laska_core`, `laska_contracts`,
`laska_test` and `laska_cli`, version `0.2.0`. The first version of every package is published
by hand — pub.dev only allows the automated publishing of the packages that already exist —
and the later versions are published by the tag, without a secret in the repository: the
token of pub.dev is a temporary one, which GitHub signs for the audience of pub.dev.

### The examples of the repository

The examples are real services that run and whose tests are part of the gate of the
repository, so a change of the framework that breaks them is caught before it is published.

| Example | What it holds |
|---|---|
| `example/contract_slice` | The vertical slice: the contract, the generated code, the service and the client. |
| `example/auth_service` | The authentication of the callers: the tokens, the scopes, the API keys, the sessions and the limits. |
| `example/database_service` | The data layer: the migrations, the repository, the transactions and the readiness of the service. |
| `example/workspace` | A workspace of two services: the service that keeps the records and the one that calls it through the client of its contract. |

The guide of the examples is `docs/examples.md`.

### Totals

| Milestone | Scope | Effort |
|---|---|---|
| v1.0 (Phases 0–6) | Core + contracts + observability + resilience + workspace | ~70–100 dev-days (≈4–5 months part-time) |
| v1.1 | pure-Dart `.proto` parser, `@injectable` codegen, ORM adapters, Redis/NATS backends | additive |

---

## 7. Explicitly out of scope for v1

- **An ORM with codegen** (use `package:postgres` + SQL migrations; adapters later, separately).
- **Admin panel** — Django's differentiator, not the audience's need. A service may carry the
  frontend of a workspace, but Laska does not build the panel itself (§4.14).
- **Server-side templates** — Jaspr covers the template/site niche in Dart. The runtime answers
  with HTML, and the application writes it (§4.14).
- **The build of the frontend** — the bundler of the application builds it, the runtime serves the
  result (§4.14).
- **Realtime WebSocket framework** — Serverpod's territory.
- **GraphQL**, multi-tenancy, i18n, file uploads, mailer.
- **Redis as a requirement** (Postgres-only is enough to start; Redis drivers are additive).
- **Service discovery via Consul/Kubernetes** — static config first.
- **An upgrade/migration path for the *old* Laska app API** (this is a breaking rewrite; the old API
  is preserved only in git history).

---

## 8. Risks and mitigations

| Risk | Impact | Mitigation |
|---|---|---|
| `laska_core` depends on the OpenTelemetry SDK, which pulls in `grpc` and `protobuf` | Every service carries a bigger dependency tree | The `Tracer` abstraction is the seam: the implementation can move to its own package without a change in the API. The SDK stays pure Dart, so the AOT binary still has no native toolchain |
| The pure-Dart parser drifts from the protobuf specification | Contracts compile here but not with `protoc` | The parser only claims the subset it implements and errors out on everything else; `protoc` stays available as a CI cross-check |
| The parser has to grow with protobuf (proto2, the extensions) | Growing maintenance surface | Each addition is a separate, testable step; the contract model does not change when the parser does |
| Foreign-language SDK generation is a maintenance multiplier | Cost per language | Orchestrate upstream protoc plugins; do not maintain our own codegen per language |
| Codegen maintenance burden grows with every protobuf feature | Phase 2+3 slip | Generate only what we consume; the parser and the generator are separate layers |
| Dart OTel SDK is beta and its ownership is in flux (donation under review) | Telemetry churn | Own the `Tracer`/`Meter`/`Logger` abstraction; the OTel SDK is one implementation behind it |
| Scope creeps back toward "mini-Django" | Never ships, and lands on Serverpod's turf | Every feature must map to §0.2 or §0.3; the phase gates are the control |
| "Contract-first" feels heavier than Go's "just write a handler" | Adoption friction | The contract is *generated into*; users write plain Dart. `laska new service` produces a working contract-driven service in one command |
| Generated clients for 5 languages is a maintenance multiplier | Cost per language | Orchestrate upstream protoc plugins; do not maintain our own codegen per language |
| Breaker/retry defaults cause cascading retries under load | Outage amplification | Retries off by default for non-idempotent methods; budgets enforced per dependency; documented defaults |
| Two-person-month scale for one developer | Burnout | Hard phase gates; v1.0 is the first shippable target and it is deliberately narrower than the vision |
| The old Laska API disappears | Migration friction for existing users | A documented "multi-isolate was never safe for stateful apps" note in the v1 migration guide |

---

## 9. Deferred decisions

Resolve during the relevant phase, not now:

- ~~Pure-Dart `.proto` parser~~ — done in Phase 2 (§4.3); `protoc` stays as a CI cross-check.
- Whether contract codegen runs via `build_runner` or a standalone `laska contract generate` —
  Phase 2 start.
- `Tracer` implementation if `dartastic_opentelemetry` changes ownership — Phase 3.
- Broker choice for the queue backend (Postgres `SKIP LOCKED` vs NATS vs Redis Streams) — the
  transactional outbox landed in Phase 4; the broker itself is still open.
- Language priority for foreign client SDKs (Go first, then PHP/Python/TS) — Phase 2.
- Whether `laska` ships a VS Code extension / language server — after v1.0.
- ~~Whether the umbrella package `laska` is published to pub.dev or stays a workspace root~~ —
  resolved at the first release: it stays a workspace root, because a workspace root cannot be
  published, so a service depends on `laska_core`.

---

## 10. Immediate next steps

Phase 1 (core runtime), Phase 2 (contract pipeline), Phase 3 (observability), Phase 4
(inter-service calls and resilience), Phase 5 (workspace and CLI maturity) and Phase 6 (release
hardening) are implemented. The framework now covers the whole path from the contract to the running
service, and the release hardening closed the gaps a v1.0 cannot have.

1. **Publish the packages** — `laska_core`, `laska_contracts`, `laska_cli` and `laska_test` on
   pub.dev, so a scaffolded project resolves its dependencies instead of a local workspace. This is
   the first thing that stands between the repository and the v1.0.
2. **The SDKs of the other languages** — the generator writes the Dart client today; the Go client
   comes first, then the Python, the TypeScript and the PHP ones. Every SDK is generated from the
   same contract, so the clients of a service agree with each other by construction.
3. **The gRPC server of the contract is done** — the runtime serves the methods of a contract under
   the name of the contract, and the generated code registers the service over gRPC next to its REST
   projection. What is left is the reflection of the server, so a tool of the ecosystem discovers
   the methods of a running service.
4. **The frontend of the workspace** — a service may carry the frontend of the workspace, and the
   runtime serves the files of a directory and answers with HTML (§4.14). The runtime is done; the
   headers of a call in the generated Dart client come next (so the frontend passes the token of
   the session), and then the scaffold `laska new app` with the kind `app` in the manifest of the
   workspace.

Deferred to v1.1: the `@injectable` codegen, the ORM adapters and the Redis and NATS backends.

---

## Appendix — competitive context (why this is still worth building)

- **Serverpod** (4.1.0) — the strongest batteries-included Dart backend: ORM, migrations, auth,
  cache, WebSocket streaming, testing framework, its own web server (Relic), Docker/Terraform,
  5000+ tests. It targets Flutter teams. This is the market Laska is **not** entering.
- **Jaspr** (0.23.5) — full-stack SSR/SSG framework, Flutter-shaped components; powers dart.dev
  and flutter.dev. It owns the "Django-ish templates in Dart" niche. Not a backend framework.
- **dart_frog** — file-based routing on shelf + mason, strong DX for simple REST APIs, but no
  contracts, no observability story, no inter-service tooling.
- **shelf / Relic** — the low-level substrate. Deliberately bypassed (§4.6).
- **rpc_dart** — transport-agnostic RPC with contracts, streaming, gRPC reflection, an OTel module
  and a framework layer (DI, lifecycle, rate limiting). Closest thing to the transport layer of
  this plan; worth studying, and a candidate to build *on* rather than duplicate.
- **Connect** (Dart v2, stable) — protobuf over HTTP/1.1/2 with gRPC and gRPC-Web interop.
  Protocol-level interoperability is solved; Laska should use it, not reinvent it.
- **dartastic_opentelemetry** — the de facto OTel SDK for Dart, being donated to the OpenTelemetry
  project. The default telemetry implementation.
- **`ormed` / `dart-orm` / `drift`** — the Dart ORM landscape, actively converging. Reason enough
  to keep Laska out of the ORM business (§4.13).
- **Kratos** (Go) — the reference architecture: API-first protobuf, generated HTTP + gRPC from one
  contract, pluggable registry/config/encoding, middleware for recovery/logging/validation/
  tracing/metrics/auth, OpenAPI + codegen workflows, contrib ecosystem. Laska is the Dart-shaped
  version of this, minus the ecosystem depth.
- **Encore.ts** — infrastructure-aware backend framework: declare infra in code, built-in tracing,
  type-safe inter-service calls, managed database and Pub/Sub. The "one tool instead of five"
  promise Laska wants to make for Dart.
- **AdonisJS** — the batteries-included benchmark (Lucid ORM, VineJS validation, policies, IoC
  container, CLI, and a typed HTTP client generated from routes). Laska copies the *typed client
  generated from the contract* idea and drops the ORM.
- **Django / Laravel / FastAPI** — the audience's current mental models, not competitors.

**The gap:** nobody in Dart owns "contract-first, observability-first, polyglot service
framework". Serverpod owns batteries-for-Flutter. Jaspr owns templates-for-Flutter-devs.
dart_frog owns "simple REST on shelf". Laska can own "one contract, many languages, one binary,
traces included".
