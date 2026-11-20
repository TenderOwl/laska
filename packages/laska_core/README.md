# laska_core

The core runtime of [Laska](https://github.com/tenderowl/laska), a contract-first
service framework for Dart.

It holds the HTTP pipeline (routing, middleware, error rendering), the process
model (workers, graceful shutdown), the data layer, the telemetry and the
authentication of the callers.

```dart
import 'package:laska_core/laska_core.dart';

final app = Laska();

app.get('/v1/users/:id<int>', (ctx) => ctx.json(<String, Object?>{
      'id': ctx.params['id'],
    }));

await run(app);
```

## What it holds

- **Routing** — static segments, `:param`, `:param<int>` (also `float`, `bool`,
  `uuid`, `slug` and custom regular expressions), optional `:param?` and the `*`
  wildcard. The tables of the router are built when a route is registered.
- **Middleware** — the order is global → group → route → handler.
- **Errors** — `HttpException` renders as an RFC 9457 `application/problem+json`
  document.
- **Observability** — OpenTelemetry tracing, Prometheus metrics, correlated
  structured logs and the health probes.
- **Resilience** — the timeout, the retry, the circuit breaker, the bulkhead and
  the idempotency of the calls to the other services.
- **Authentication** — the tokens (JWT), the JWKS, the API keys, the sessions and
  the rate limiting.
- **Files and HTML** — `app.staticFiles(prefix, directory)` serves the files of a
  directory with the content type of their extension and with the validators of
  the cache, and `ctx.html(...)` answers with a document of HTML.

## The documentation

The guides live in [docs/](https://github.com/tenderowl/laska/tree/main/docs):
getting started, contracts, observability, resilience, authentication,
versioning, compatibility and performance.

## The licence

MIT — see [LICENSE](LICENSE).
