## Unreleased

- Repositioned the project: Laska is now a **contract-first service framework** (protobuf
  contracts → REST + gRPC + typed clients in Dart/PHP/Python/Go/TS, OpenAPI export, breaking-change
  detection), with observability, resilience and multi-service workspace tooling as first-class
  features. The Django-style "batteries included" direction was dropped in favour of
  contract-first operations for polyglot teams.
- Rewrote `PLAN.md` around the new positioning: 5 packages instead of 11, SQL-first data access
  instead of a framework ORM, and contracts + observability moved ahead of the ORM work.
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
