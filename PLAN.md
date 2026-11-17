# Laska — Product & Architecture Plan

> **Laska is a contract-first service framework for Dart.**
> One contract → typed server stubs + typed clients in any language, observability and
> resilience built in, one binary to deploy.

**Status (2026-11-17):** Phase 2 is implemented as a working vertical slice — `.proto` →
Dart messages, service interface, REST routes, typed client, OpenAPI 3.1 and a
breaking-change check. The contract pipeline ships with a **pure-Dart `.proto` parser**
instead of `protoc`, which removes the native toolchain from the critical path entirely
(§4.3). See §6 for what is done and what is left.

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

## 1. Where Laska stands today

Audit of the current tree (`lib/` is ~700 lines of real code, last commit 2024-08-01).

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

### Missing entirely

DI container · request validation · config/env loading · structured logging · graceful shutdown ·
contract tooling (protobuf compilation, codegen, breaking-change detection) · OpenAPI export ·
distributed tracing · metrics · health/readiness probes · inter-service clients · resilience
primitives (retry, circuit breaker, bulkhead, idempotency) · workspace/multi-service tooling ·
SQL migrations · auth (JWT / session / API key) · rate limiting · CLI · test harness.

**Test coverage today:** the router only. Nothing exercises the server, the middleware chain,
error paths, or the isolate model.

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
laska/
├── packages/
│   ├── laska_core/        # app, router, request/response, middleware, DI, config,
│   │                      # errors, lifecycle, supervisor, telemetry, resilience, SQL migrations
│   ├── laska_contracts/   # contract compilation, codegen, client generation, diffing, OpenAPI
│   ├── laska_cli/         # the `laska` CLI
│   ├── laska_test/        # test harness: app builder, HTTP client, fixtures, fake telemetry
│   └── laska/             # umbrella package — what apps depend on
├── example/
├── docs/
└── tool/                  # repo-level checks
```

**Deliberately smaller than the previous plan (11 → 5).** Telemetry and resilience live inside
`laska_core` until they prove they need their own release cadence; they are the kind of
feature that gets adopted only if it is one import away. `laska_contracts` is separate because
its dependency surface (codegen, protoc, buf) differs from the runtime and would otherwise
weigh down every service that only wants to serve HTTP.

All packages version in lockstep. The umbrella package `laska` pins the rest.

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
  supports it). Where it is unavailable, the supervisor falls back to `SO_REUSEADDR` with accept
  balancing at the supervisor level.
- Worker count defaults to `min(cores, 8)`, overridable by `--workers` / `LASKA_WORKERS`.
- Health: supervisor restarts crashed workers, drains on SIGTERM (graceful shutdown: stop accepting,
  finish in-flight requests within a timeout, flush queues, close pools).
- **Every app must be safe to run as N processes.** No in-process global state as a source of truth.

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
| OpenAPI 3.1 document | docs, client generators, gateway | done |
| Breaking-change report (`laska contract diff`) | CI | done |
| gRPC service descriptor + client stub | other services | planned |
| PHP/Python/Go/TS client SDKs | consumers in other languages | planned |
| Binary protobuf codec | wire compatibility with other languages | planned |

**Wire format of the slice:** the generated messages follow the protobuf JSON mapping
(field names in lowerCamelCase, enums by their proto name), and the REST projection speaks
JSON. The binary protobuf codec and the gRPC transport are Phase 4 work — the contract
model, the generator and the diff already carry everything they need.


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

- The parser covers the subset Laska needs: `syntax`, `package`, `import` (recorded, not
  resolved), messages with scalar/message/enum/repeated/optional fields, enums, services
  and `google.api.http` bindings including `additional_bindings` and `body`.
- Constructs outside that subset (`oneof`, `map`, nested messages and enums) raise a
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

**Still to come:** `bytes` fields, `oneof`, `map`, nested types, well-known types, proto2
syntax, and `optional` semantics beyond presence tracking. When the subset outgrows the
parser, `protoc` stays available as a cross-check in CI — the generated model is the same
either way.


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

`laska contract diff <base> --against <head>` compares two contract snapshots and fails on
breaking changes, using Buf's semantic rules (field number reuse, type change, removal of a
field, changing a required method, and so on).

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
| `/users/:id<int>` | parameter with a constraint (`int`, `uuid`, `float`, `slug`, or a regex `/^\d{4}$/`) |
| `/users/:id?` | optional trailing parameter |
| `/files/*` | wildcard (rest of path) |
| `ANY` | any HTTP method |

Features:

- **Route groups** with prefix + middleware + scope: `app.group('/admin', () {...}, prefix: '/v1')`.
- **Named routes** and a URL generator: `Url.for('users.show', {id: 1})` → `/v1/users/1`.
- **405 with an `Allow` header** — the matcher knows which methods exist for a path.
- **Deterministic priority**: static > parameter > wildcard, with constraints narrowing the
  parameter branch first. No "last registered wins" ambiguity.
- **Contract-driven routes** — routes generated from `google.api.http` annotations are registered
  through the same matcher, so hand-written and generated routes coexist with one priority model.
- Keep the static-route hashmap fast path from the current implementation.
- `laska route:list` prints the full route table (method, path, name, middleware, handler).

### 4.8 Middleware — explicit, ordered, onion model

```dart
typedef Next = Future<void> Function();
abstract class Middleware {
  Future<void> handle(Request ctx, Next next);
}
```

- Order is **global → group → route → handler**, and it is *specified*, not incidental.
- Named/aliased middleware: `app.use('auth', AuthMiddleware())`, then `app.get('/me', h, middleware: ['auth'])`.
- Global middleware can be excluded per route (`app.get('/health', h, skip: ['cors'])`).
- A middleware short-circuits by not calling `next` (replaces the current "return null" convention,
  which is easy to get wrong).
- The middleware chain is the **single instrumentation point**: tracing, metrics, logging and
  request-id propagation are implemented as built-in middleware, not as user-installed packages.
  This is why observability is cheap to adopt and impossible to retrofit later without breaking
  the API.

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

- **Tracing**: integrate `dartastic_opentelemetry` (Apache-2.0) as the default implementation
  behind an internal `Tracer` abstraction, so the SDK can be swapped when the official Dart OTel
  SDK (currently in donation review at the OpenTelemetry project) lands. Traces, metrics and logs
  with OTLP/gRPC and OTLP/HTTP exporters.
- **Auto-instrumentation**: the framework creates spans for inbound requests, outbound service
  calls, SQL queries (via a driver wrapper) and queue jobs. Users get a useful trace without
  writing a single span.
- **Logs**: structured JSON with `trace_id`, `span_id`, `service`, `version` and `request_id`
  on every line, so `laska dev` and any log aggregator can join them.
- **Metrics**: `/metrics` in Prometheus text format — request count/latency by route, error rate,
  dependency call latency, pool saturation.
- **Probes**: `/healthz` (liveness) and `/readyz` (readiness, gated on DB/queue state).
- **Configuration**: standard `OTEL_*` environment variables, so an existing OTel collector
  works with no Laska-specific setup.

**Why this is a differentiator:** Dart is still the last top-15 language without an officially
maintained OTel SDK. A framework that ships OTel as a first-class, opinionated part of the
runtime turns a gap in the ecosystem into the framework's reason to exist.

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

---

## 5. Feature specs

### 5.1 `laska_core`

- `Laska` app object: `config`, `use`, `group`, route verbs, `singleton`/`bind`, `onStart`/`onShutdown`.
- `Request` — method, path, `uri`, headers, cookies, `body()` (JSON/form/multipart/text/raw), `query`,
  `params`, `route`, `ip`, `userAgent`, `contentType`.
- `Response` — `json`, `text`, `html`, `redirect`, `status`, `stream`, `file`, `attachment`.
- `Context` — request + response + `session` + `auth` + `app` + `logger` + `tracer`.
- `Config` — typed config classes loaded from `config/*.dart` + env overrides (`.env` via `package:dotenv`),
  with secret redaction in logs.
- `Logger` — structured JSON output, request-id and trace-id correlation.
- Lifecycle hooks: `onStart`, `onReady`, `onShutdown`; graceful shutdown with in-flight drain and timeout.
- Built-in middleware: tracing, metrics, request logging, request-id, recovery, CORS, rate limit,
  security headers.
- Auth: JWT (via `package:jose`), signed session cookies, API keys; pluggable guard interface.
- `Db` helper over `package:postgres` / `package:sqlite3`, plus the SQL migration runner.

### 5.2 `laska_contracts`

- Contract compilation with a managed, cached `protoc`.
- Dart codegen: messages, service interfaces, REST route registration, typed clients, DI wiring.
- Foreign-language SDK generation by orchestrating upstream protoc plugins
  (`--lang=go`, `--lang=php`, `--lang=python`, `--lang=ts`).
- OpenAPI 3.1 export from the same contract, served at `/api-docs` in dev and exportable as a
  static file in CI.
- `laska contract diff` — breaking-change detection with Buf-compatible semantics.
- `laska contract lint` — naming, field-naming and package-layout rules, in CI.

### 5.3 `laska_cli`

```
laska new <name>          # scaffold a project
laska new service <name>  # scaffold a service inside a workspace
laska serve [--workers=N] # run the HTTP server (supervisor)
laska dev                 # run all services of a workspace + local infra + aggregated logs
laska contract compile    # compile contracts, generate code
laska contract generate --lang=go
laska contract diff <base>
laska contract lint
laska route:list          # dump the route table
laska migrate:make <name> # scaffold a SQL migration
laska migrate:run|status|rollback
laska db:seed
laska build               # AOT compile
laska dockerfile|k8s      # deployment artifacts
```

Built on `package:args`. `laska serve` is the supervisor described in §4.1. `laska dev` is the
single most valuable command for the target audience: it starts every service in the workspace,
wires them to a local Postgres/Redis (via a generated compose file), aggregates their logs, and
shows live traces — the "one command instead of five tools" promise in practice.

### 5.4 `laska_test`

- `testClient(app)` → `.get('/users').expect(200).json({...})`.
- In-memory SQLite for fast unit tests; Postgres via compose for integration tests.
- Fixtures/seed helpers, DB transaction rollback between tests, fake cache/session/queue/telemetry.
- Contract test helpers: assert that the implementation matches the generated service interface,
  and golden-file tests for the OpenAPI document.

---

## 6. Milestones

Assume one developer at ~20 h/week. Sizes are rough.

### Phase 0 — Groundwork (3–5 days)

- [ ] Restructure into a pub workspace; move existing code under `packages/laska_core` with `git mv` (history preserved).
- [ ] CI: `dart analyze`, `dart format --set-exit-if-changed`, `dart test` on Linux + Windows + macOS.
- [ ] Commit/branch/lint policy; `CONTRIBUTING.md`; changelog process.
- [ ] Publish skeleton packages to pub.dev.

**Done when:** `laska serve` boots an empty app; CI green on all three OSes.

### Phase 1 — Core runtime (12–18 days) — *started*

- [x] `Request` / `Response` / `Context` over `dart:io`.
- [x] Router: static segments, `:param`, `*` wildcard, static fast path, groups with prefix
      and middleware, 405 + `Allow` header.
- [x] Middleware pipeline with explicit ordering (global → group → route → handler).
- [x] `HttpException` + RFC 9457 `application/problem+json` rendering.
- [ ] Parameter constraints (`:id<int>`), named routes, `route:list`.
- [ ] Middleware aliases, the built-in middleware set, request ids.
- [ ] Config (`config/*.dart` + env), structured logging with redaction.
- [ ] Graceful shutdown, supervisor (`laska serve`), worker crash-restart.
- [ ] `Db` helper + SQL migration runner.
- [ ] `laska_test` harness with the HTTP client.

**Done when:** a route with a param constraint, a group with middleware, and a JSON 422 all behave
as specified, with tests — *partially done*: the parts marked above exist and are covered by
`packages/laska_core/test`, the rest is still open.


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
- [ ] Foreign-language client generation (`--lang=go` first, then PHP/Python/TS).
- [ ] Binary protobuf codec and the gRPC transport.

**Done when:** one `.proto` produces a working REST endpoint, a Dart client, an OpenAPI
document and a CI check that fails on a breaking change — **done**; the gRPC transport and
the foreign-language SDKs are what is left.


### Phase 3 — Observability (10–14 days)

- [ ] `Tracer` abstraction + `dartastic_opentelemetry` implementation; `OTEL_*` env configuration.
- [ ] Auto-instrumentation: inbound requests, outbound calls, SQL, queue jobs.
- [ ] Structured logs correlated by `trace_id`/`span_id`/`request_id`.
- [ ] Prometheus `/metrics`, `/healthz`, `/readyz`.
- [ ] `laska dev` workspace runner with aggregated logs and a local collector.

**Done when:** a request through two services shows up as one trace, with metrics and correlated
logs, with no instrumentation code written by the user.

### Phase 4 — Inter-service & resilience (12–16 days)

- [ ] Generated client with per-method timeout/retry defaults.
- [ ] Retry with backoff + jitter, idempotency-key propagation.
- [ ] Circuit breaker, bulkhead, graceful degradation.
- [ ] Outbox helper (transactional publish).
- [ ] Service discovery via static config; gRPC + HTTP transports for the same contract.

**Done when:** a dependency failure produces a circuit-open response in 5 seconds instead of a
pile-up, and the retry policy is visible in the contract.

### Phase 5 — Workspace & CLI maturity (10–14 days)

- [ ] `laska.yaml` workspace manifest, multi-service `laska dev`.
- [ ] `laska new service`, scaffolding from a contract template.
- [ ] Dockerfile + Kubernetes manifest generation.
- [ ] CI recipes: `analyze`, `test`, `contract diff`, `contract lint`.
- [ ] Docs: getting started, contracts, observability, resilience, deployment.

**Done when:** a two-service workspace runs from `laska dev` on a fresh machine with one command.

### Phase 6 — Release hardening (8–12 days) → **v1.0**

- [ ] Auth hardening: key rotation, JWKS support, session fixation defence, rate limiting.
- [ ] Semver policy, upgrade guide, `laska upgrade` codemods.
- [ ] Contract compatibility matrix, end-to-end example service published.
- [ ] Performance pass on the hot path (buffer reuse, precomputed route tables, allocation budget).

**Done when:** `laska new` produces a two-service workspace with contracts, generated clients,
tracing, resilience and passing tests — this is **v1.0**.

### Totals

| Milestone | Scope | Effort |
|---|---|---|
| v1.0 (Phases 0–6) | Core + contracts + observability + resilience + workspace | ~70–100 dev-days (≈4–5 months part-time) |
| v1.1 | pure-Dart `.proto` parser, `@injectable` codegen, ORM adapters, Redis/NATS backends | additive |

---

## 7. Explicitly out of scope for v1

- **An ORM with codegen** (use `package:postgres` + SQL migrations; adapters later, separately).
- **Admin panel** — Django's differentiator, not the audience's need.
- **Server-side templates** — Jaspr covers the template/site niche in Dart.
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
| The pure-Dart parser drifts from the protobuf specification | Contracts compile here but not with `protoc` | The parser only claims the subset it implements and errors out on everything else; `protoc` stays available as a CI cross-check |
| The parser has to grow with protobuf (`oneof`, `map`, well-known types) | Growing maintenance surface | Each addition is a separate, testable step; the contract model does not change when the parser does |
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

- Pure-Dart `.proto` parser — v1.1, after the protoc path is proven.
- Whether contract codegen runs via `build_runner` or a standalone `laska contract generate` — Phase 2 start.
- `Tracer` implementation if `dartastic_opentelemetry` changes ownership — Phase 3.
- Broker choice for the queue backend (Postgres `SKIP LOCKED` vs NATS vs Redis Streams) — Phase 4.
- Language priority for foreign client SDKs (Go first, then PHP/Python/TS) — Phase 2.
- Whether `laska` ships a VS Code extension / language server — after v1.0.

---

## 10. Immediate next steps

1. Confirm this plan (or amend §6 phases).
2. Phase 0: create the pub workspace skeleton and move `lib/` → `packages/laska_core/`.
3. Replace the vendored `http_body.dart` with `package:http_parser`.
4. Write the router v2 spec as tests first (constraints, groups, 405), then implement.
5. Land `laska serve` + the supervisor with graceful shutdown.
6. Prototype the contract pipeline early (Phase 2 is the risk): one `.proto` → REST route + Dart
   client + OpenAPI + a failing `contract diff`. Everything else is downstream of this.

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
