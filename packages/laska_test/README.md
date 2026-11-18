# laska_test

The test harness of [Laska](https://github.com/tenderowl/laska): an in-process
HTTP client, the expectation helpers, the database helpers, a fake tracer and a
fake transport.

```dart
import 'package:laska_test/laska_test.dart';

final client = testClient(app);

final response = await client.get('/v1/users/u_1');
response.expectStatus(200);
```

## What it holds

- **The in-process client** — the request goes through the same dispatcher as
  the HTTP server, so a test covers the routes, the middleware and the error
  rendering without opening a socket.
- **The fake transport** — a generated client answers from the test, so the
  retries, the breaker and the bulkhead are covered by a unit test.
- **The fake tracer** — a test asserts which spans were created and which trace
  they belong to.
- **The database helpers** — the body of a test runs in a transaction that is
  rolled back afterwards.

## The documentation

The guide of the tests lives in
[docs/getting-started.md](https://github.com/tenderowl/laska/blob/main/docs/getting-started.md).

## The licence

MIT — see [LICENSE](LICENSE).
