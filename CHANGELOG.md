## Unreleased

- **The distribution of the framework:**
  - **The packages of the framework are published on pub.dev** as `laska_core`,
    `laska_contracts`, `laska_test` and `laska_cli`, version `0.1.0`. The command of
    the line is installed with `dart pub global activate laska_cli`, and the release
    `v0.1.0` of the repository holds the bundle of the command for Linux, macOS and
    Windows, on x64 and on arm64.
  - The publishing needs no secret in the repository: the token of pub.dev is a
    temporary one, which GitHub signs for the audience of pub.dev with the permission
    `id-token: write`. The first version of a package is published by hand, because
    pub.dev only allows the automated publishing of the packages that already exist.
  - The packages of the workspace are ready for pub.dev: the metadata of the
    four packages, the `LICENSE`, the `README.md` and the `CHANGELOG.md` of each
    of them, and the `executables:` that names the command `laska`.
  - `tool/publish.dart` publishes a package out of the workspace: it copies the
    package, takes the `resolution: workspace` line out of the pubspec — a
    package of a workspace cannot be published with it — and runs
    `dart pub publish` there. The tree of the repository has to be clean, so
    the files that are published are the files that are committed.
  - The release is a tag: `.github/workflows/release.yml` checks that the tag
    matches the version of the packages, builds the bundle of the command line
    interface for Linux, macOS and Windows on x64 and on arm64, publishes the
    packages on pub.dev and opens the release of the repository with the
    archives and their checksums.
  - The installer puts the command in place without the Dart SDK:
    `tool/install.sh` and `tool/install.ps1` download the bundle of the
    platform, check its SHA-256 before they unpack it and print the line that
    puts the command in the PATH.

- **Implemented the release hardening (Phase 6):**
  - **The authentication of the callers.** `laska_core/src/auth/` holds the tokens
    (`HS256`, `RS256/384/512`, `ES256/384/512`), the API keys, the sessions and the
    rate limiting. The verifier does not trust the header of a token: the algorithm of the
    token has to be the algorithm of the key that signed it, so `alg: none` and the
    confusion of the algorithms are refused. Every failure answers with a `401` or a
    `403` that does not tell what is wrong with the secret of the caller.
  - **The keys of the service and their rotation.** The key set of a service is published
    as a JWKS, and the cache of the set refreshes it when a token names a key it does not
    know — never more than once every ten seconds, so a flood of made-up `kid`s cannot
    turn the service into a client of itself. `laska keys generate` writes the private key
    in a file of its own and the public key set next to it.
  - **The sessions.** The id of a session is regenerated when the privileges of the
    session change, so an id that leaked before the login is dead afterwards: that is the
    defence against the fixation of a session. The cookie is written with `HttpOnly`,
    `Secure` and `SameSite`.
  - **The rate limiting.** A token bucket per caller: the principal or the API key when the
    caller is known, its address otherwise, so the limit follows the caller and not the
    connection. The caller that asks for too much gets a `429` and a `retry-after`.
  - **The policy of the versions.** A breaking change goes to the next major version of the
    API, and a change that breaks nobody stays in the version it is in. The rule is
    checked by `laska contract diff`, which fails with the exit code 1 when the version of
    the candidate does not follow it. `laska upgrade --api users --from v1 --to v2` moves
    the contract, the generated code and the calls of the service together.
  - **The matrix of the compatibility.** `laska contract matrix` compares every version of
    a contract with every other one and tells which client works against which server: the
    versions that were added, the ones the server lost, and the paths that differ because
    the version of an API lives in the paths of its REST projection.
  - **A workspace that runs as it is.** `laska new <name>` writes two services: the first
    one keeps the records, the second one calls it through the typed client of its
    contract. The trace of the caller goes from one service to the other, so the project
    shows the whole path of the framework. `laska dev` resolves the dependencies of every
    service before it starts it.
  - **The performance of the hot path.** The tables of the router are built when a route
    is registered, the expressions of the constraints are compiled once, the chain of the
    middleware of a route is built once and kept, the request is not copied for the
    parameters of its route, and the body of a request is read into a buffer that comes
    from a pool. The budget of the hot path is a number of objects per request, and the
    tests hold the runtime to it. `tool/benchmark.dart` measures it.
  - The guides of the release live in `docs/`: authentication, versioning, upgrading,
    compatibility and performance.

- **Implemented the workspace and the CLI maturity (Phase 5):**
  - `laska new service <name>` writes a service that runs: the contract, the
    generated code, the implementation, the entrypoint, a test and the manifest of
    the package. `laska new <name>` writes a whole workspace with a first service
    in it. The `--local` flag makes the project depend on the packages of a local
    Laska workspace, which is what a checkout needs while the packages are not
    published.
  - The manifest of the workspace grew: an `environment` for the whole workspace
    and a `depends_on` for a service. `laska dev` starts the services in the order
    of their dependencies, waits for the services a service depends on to answer
    before it starts it (`--startup-timeout`), and gives every service the address
    of the other ones (`USERS_URL`), which is what the service discovery of the
    runtime reads.
  - The manifest is read by a pure-Dart YAML parser that ships with the CLI
    (`packages/laska_cli/lib/src/yaml.dart`): nested maps, lists of scalars, lists
    of maps, inline lists, comments and quotes. An unknown dependency and a cycle
    of dependencies are reported before anything is started.
  - `laska deploy:dockerfile` and `laska deploy:k8s` write the images and the
    Kubernetes manifests of the services of the workspace. The Dockerfile compiles
    the service with the Dart SDK and the runtime image holds the binary alone.
  - `laska contract lint` checks the contract against the rules of the framework:
    a versioned package that matches the name of the file, the messages and the
    services in PascalCase, the services ending with `Service`, the fields in
    snake_case and the values of the enums in UPPER_SNAKE_CASE. The command fails
    with the exit code 1 when it finds a problem.
  - `laska ci:recipe` writes the recipe of the continuous integration: the
    format, the analyzer, the tests, the lint of the contract and the comparison
    of the contract with its baseline.
  - The guides live in `docs/`: getting started, contracts, observability,
    resilience and deployment.
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
