## Unreleased

- **Implemented the inter-service and resilience layer (Phase 4):**
  - **The policy of a call is written in the contract.** A service (or a single method) declares
    `option (laska.policy) = { timeout_ms, max_attempts, backoff_ms, max_backoff_ms, jitter,
    idempotent }`, the parser reads it, and the generator turns it into a `<Service>Policies` class
    that the generated client applies to every call. The retry policy is therefore visible to
    everyone who reads the contract, not only to the code of the caller.
  - `DependencyPolicy`, `Dependency`, `CircuitBreaker`, `Bulkhead`, `RetryPolicy` and the error
    taxonomy (`DependencyFailure`, `DependencyTimeoutException`, `CircuitOpenException`,
    `BulkheadFullException`, `ServiceNotFoundException`) in `laska_core/src/resilience/`.
    `Dependency` is the one place where the bulkhead, the breaker, the per-attempt timeout and the
    retry loop meet, and it traces the call as one client span with the number of the attempts.
  - Retries happen **only for idempotent calls**: a call that changes something is never repeated
    and gets an `idempotency-key` header instead. The backoff grows exponentially, is capped, is
    randomised with jitter and honours `Retry-After`.
  - The breaker counts the **attempts**, not the calls: a dependency that fails three times in a
    row opens the circuit, and the calls that follow fail fast with `503` instead of piling up.
  - The bulkhead limits the concurrency per dependency, so one slow dependency cannot exhaust the
    process; the queue of the waiting calls is bounded too.
  - The idempotency store and its middleware replay the first answer of a repeated key and mark it
    with the `idempotency-replayed` header.
  - The transactional outbox: the business row and the event are written in one transaction, and a
    dispatcher publishes the pending events and marks them sent — at-least-once delivery without a
    distributed transaction.
  - Static service discovery from `LASKA_SERVICES` or `<NAME>_URL`; an unknown service is an error
    instead of a silent default.
  - One error taxonomy: the HTTP status, the gRPC status and the machine readable code of every
    failure of a dependency live in one place (`httpStatusOfError`, `errorCodeOf`).
  - **Two transports for one contract**: `HttpServiceTransport` speaks JSON over the REST
    projection, `GrpcServiceTransport` speaks the binary protobuf over the RPC path, and the
    generated client works with both. The binary protobuf codec is pure Dart
    (`ProtoWriter`/`ProtoReader`), so no `protoc` and no native toolchain are needed.
  - `laska_test` gained a `TestTransport`: it answers with what the test prepared and records the
    requests, so the retries, the breaker and the bulkhead of a client are covered without a
    network.
- **The command line interface has a help.** `laska --help` (or `laska -h`, or `laska help`) prints
  the list of the commands, the global options and the environment variables of the telemetry, and
  `laska help <command>` describes one command with its options and its defaults. Every command also
  answers `--help` on its own. The help is built from the parser, so it cannot drift away from the
  commands and the options that are actually there. An unknown command is reported and exits with
  the code `64` instead of printing the help as if nothing happened.
- The commands of the CLI moved to `laska_cli/src/cli.dart` behind `runCli(arguments, {out, err})`,
  and the executable only forwards the result to the process. A test can therefore drive the
  commands in process, which made the suite of the CLI about fifteen times faster and removed the
  timeouts it hit on a loaded machine.
- Repositioned the project: Laska is now a **contract-first service framework** (protobuf
  contracts → REST + gRPC + typed clients in Dart/PHP/Python/Go/TS, OpenAPI export, breaking-change
  detection), with observability, resilience and multi-service workspace tooling as first-class
  features. The Django-style "batteries included" direction was dropped in favour of
  contract-first operations for polyglot teams.
- Rewrote `PLAN.md` around the new positioning: 5 packages instead of 11, SQL-first data access
  instead of a framework ORM, and contracts + observability moved ahead of the ORM work.
- **Implemented the observability layer (Phase 3):**
  - A `Tracer` abstraction in `laska_core`, with the OpenTelemetry SDK
    (`dartastic_opentelemetry`, Apache-2.0) as the default implementation behind it, so the SDK
    can be replaced without touching the runtime. The standard `OTEL_*` environment variables
    configure it: `OTEL_SERVICE_NAME`, `OTEL_EXPORTER_OTLP_ENDPOINT`, `OTEL_TRACES_SAMPLER_ARG`,
    `OTEL_SDK_DISABLED`.
  - Auto-instrumentation as built-in middleware: a server span per request, a client span per
    outgoing call and a span per SQL statement (`TracingDatabase`). The generated client writes the
    `traceparent` header, so a request through two services is one trace.
  - Structured logs correlated by `request_id`, `trace_id` and `span_id` — `ctx.logger` carries
    the context of the request.
  - Prometheus `/metrics` in the text exposition format, `/healthz` and `/readyz`.
  - `Observability.install(app)` wires the whole stack with one call.
  - `laska dev` — the workspace runner: it starts every service of `laska.yaml`, aggregates
    their logs in one stream and points them at a local collector that prints the traces.
  - `laska_test` gained a fake tracer, so a test can assert what a service traced.
  - The supervisor no longer restarts a worker forever: after `maxRestarts` tries it gives up and
    says so. On Windows the service runs with a single worker, because the platform has no
    SO_REUSEPORT and two processes cannot listen on the same port.
- **Implemented the core runtime (Phase 1):**
  - Router v2 — parameter constraints (`:id<int>`, `:id<uuid>`, `:id<slug>`, custom regular
    expressions), optional segments (`:id?`), wildcards, named routes, `urlFor` and a
    `route:list` table. The matcher is deterministic: static > constrained parameter > parameter >
    wildcard.
  - A `Dispatcher` that turns a `Request` into a `Response` outside of HTTP, so the server and the
    test harness run the exact same pipeline. `HttpException` renders as an RFC 9457
    `application/problem+json` document, a `FormatException` as a 400, anything else as a 500.
  - Middleware with an explicit order (global → group → route → handler), named aliases
    (`app.alias('auth', middleware)`) and a built-in set: request id, request logging, CORS and
    security headers. The chain is resolved when the request arrives, so a global middleware
    registered after a route still runs for it, and the middleware of a group never leaks into
    another group.
  - `Config` — environment over `.env`, typed accessors and secrets that are redacted in the logs;
    `Logger` — one JSON object per line, with levels and secret redaction.
  - Graceful shutdown with an in-flight drain and a timeout, and a `Supervisor` that starts the
    worker processes, restarts the ones that crash and stops them on a signal.
  - A thin data layer: `Database` over `package:postgres` and `package:sqlite3`, plus a SQL
    migration runner with a `schema_migrations` ledger and a rollback section per file.
  - `packages/laska_test` — an in-process client (`testClient(app)`) with expectation helpers and
    database helpers that roll the test data back.
  - `laska serve`, `laska route:list` and `laska migrate:run` in the CLI.
  - `run(app, arguments: args)` takes the arguments of `main`, so the framework flags
    (`--laska-route-list`, `--laska-migrate`) work however the service is started. The Dart VM does
    not report the script arguments in `Platform.executableArguments`, so they cannot be read from
    there.
- **Implemented the contract pipeline (Phase 2) as a working vertical slice:**
  - `packages/laska_core` — the runtime: router with static/`:param`/`*` segments, groups,
    ordered middleware, `Request`/`Response`/`Context`, RFC 9457 problem documents.
  - `packages/laska_contracts` — a pure-Dart proto3 parser, contract validation, a Dart code
    generator (message classes, service interfaces, REST projection, typed client), an OpenAPI 3.1
    exporter and a Buf-compatible breaking-change detector. The parser replaces `protoc`, so no
    native toolchain is needed to compile a contract.
  - `packages/laska_cli` — `laska contract compile` and `laska contract diff` (exit code 1 on a
    breaking change, for CI).
  - `example/contract_slice` — contract, generated code, service implementation and an
    integration test that exercises the whole path, including a drift check on the generated code.
- Added `tool/check.dart` (format, analyze, test) and a GitHub Actions workflow.

## 1.0.0

- Initial version, created by Stagehand
