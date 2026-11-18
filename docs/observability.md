# The observability

One call wires the whole stack — the request ids, the tracing, the metrics,
the request log and the health probes — into the service:

```dart
final app = Laska();

Observability.install(
  app,
  logger: Logger(service: 'users', version: '0.1.0'),
);

registerUsersService(app, UsersServiceImpl());

await run(app, arguments: arguments);
```

The service writes no instrumentation code.

## The traces

Every request gets a server span, every outgoing call a client span and every
SQL statement a span. The trace continues across the services: the generated
client writes the `traceparent` header and the receiving service continues
that trace, so a request through two services is **one** trace.

```dart
final tracer = OtelTracer(service: 'users');
final client = UsersServiceClient(
  baseUrl: 'http://localhost:8080',
  tracer: tracer,
);
```

The tracer is an abstraction (`Tracer`), so the OpenTelemetry SDK can be
replaced without touching the runtime. The configuration uses the standard
environment variables, so an existing collector works with no Laska-specific
setup:

```console
$ export OTEL_SERVICE_NAME=users
$ export OTEL_EXPORTER_OTLP_ENDPOINT=http://localhost:4318
$ export OTEL_TRACES_SAMPLER_ARG=1.0
```

| Variable | Meaning |
|---|---|
| `OTEL_SERVICE_NAME` | The name of the service in the traces. |
| `OTEL_EXPORTER_OTLP_ENDPOINT` | The endpoint of the collector. The telemetry stays off while it is not set. |
| `OTEL_EXPORTER_OTLP_PROTOCOL` | The protocol of the collector: `http/json` or `grpc`. |
| `OTEL_TRACES_SAMPLER_ARG` | The ratio of the traces that are recorded, between 0 and 1. |
| `OTEL_SDK_DISABLED` | Turns the whole telemetry off. |

The SQL statements are traced by the wrapper of the database:

```dart
final database = TracingDatabase(await SqliteDatabase.open('app.db'));
```

## The metrics

`/metrics` answers in the Prometheus text format, with the count and the
duration of the requests by route:

```console
$ curl http://localhost:8080/metrics
# HELP laska_http_requests_total The requests the service answered.
# TYPE laska_http_requests_total counter
laska_http_requests_total{route="GET /v1/users/:id",status="200"} 42
```

## The logs

One JSON object per line, correlated with the `request_id`, the `trace_id`
and the `span_id`. `ctx.logger` carries the context of the request, so a log
line of a handler belongs to the trace of the request that caused it.

```json
{"time":"2026-11-17T23:16:49.43Z","level":"info","service":"users","message":"request","method":"GET","path":"/v1/users/u_1","status":200,"duration_ms":3.6,"request_id":"ho9c1t5f2b","trace_id":"00000000000000000006608116c5fcb9"}
```

The secrets are redacted: a value that is written in the configuration as a
secret never reaches a log line.

## The probes

| Probe | Meaning |
|---|---|
| `/healthz` | The process is alive. |
| `/readyz` | The service is ready: the database and the queue answer. |

Both are served by the runtime, so every service of a workspace answers them
the same way.

## The workspace collector

`laska dev` starts a local collector, points the services of the workspace at
it and prints the traces it receives:

```console
$ dart run laska_cli:laska dev
=> collector on http://127.0.0.1:4318
=> users on http://127.0.0.1:8080
=> 2 service(s) started. Press Ctrl+C to stop.
collector: trace 4bf92f35 span 00f067aa http.server 12.4ms
```

The collector is a development tool: in production the services send their
telemetry to the collector of the platform.

## In a test

The harness holds a fake tracer, so a test can assert what a service traced:

```dart
final tracer = TestTracer();
Observability.install(app, tracer: tracer, logger: Logger(service: 'users'));

await client.get('/v1/users/u_1');

expect(tracer.spans.map((span) => span.name), contains('http.server'));
```
