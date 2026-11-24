# The cache of a service

Laska ships a cache, but the cache is not a feature of the framework — it is
a seam. The runtime holds an implementation that keeps the values in the
memory of the process, and a service that needs a cache shared by its workers
writes its own store behind the same interface.

Two rules shape the design:

- **The cache is a seam, not a policy.** The store holds the values; the
  policy — what is worth keeping and for how long — belongs to the service.
- **A cache belongs to a worker.** Laska runs one isolate per process, so the
  memory store is coherent inside a worker and is not shared between them. A
  service that needs a shared cache writes a store on top of Redis or of its
  database.

## The store

`CacheStore` is the interface of the cache:

```dart
abstract class CacheStore {
  Future<T?> read<T>(String key);
  Future<void> write<T>(String key, T value, {Duration? ttl});
  Future<void> delete(String key);
  Future<void> clear();
}
```

The runtime ships `MemoryCacheStore` — the default implementation:

```dart
final store = MemoryCacheStore(maxEntries: 1024);
```

The store holds at most `maxEntries` values. When it grows past the limit,
the least recently used value is forgotten. A value written with a `ttl`
expires when the ttl is over; a value written without one stays until it is
deleted.

The store is the mechanism, not the policy: it knows how to keep a value and
when to forget it, and it knows nothing about the service it serves.

## The cache

`app.cache` is the cache of the service — a `Cache` over a store. The
application creates a memory store by default, so a service may use the cache
without configuring anything:

```dart
final app = Laska();

final report = await app.cache.get<Map<String, Object?>>('report');
await app.cache.put('report', <String, Object?>{'total': 42});
await app.cache.delete('report');
```

A group inherits the cache of its application, so a service sets the cache
once, on the root:

```dart
final app = Laska();
app.cache = Cache(
  MemoryCacheStore(maxEntries: 500),
  defaultTtl: const Duration(minutes: 10),
);

app.group('/api', (group) {
  // The group uses the same cache as the application.
  group.get('/report', (ctx) async { ... });
});
```

The `defaultTtl` is how long a value lives when the caller does not say. A
value that must live until it is deleted is written through the store:

```dart
await app.cache.store.write('report', report);
```

## Remember

`remember` returns the value of a key and loads it when it is missing:

```dart
app.get('/report', (ctx) async {
  final report = await ctx.app.cache.remember('report', () async {
    final rows = await ctx.app.database!.query('SELECT * FROM sales');
    return <String, Object?>{'total': rows.length};
  });
  return ctx.json(report);
});
```

The loader runs only when the value is not cached. When a burst of calls asks
for the same key at the same time, the loader runs **once** and the calls wait
for it — the cache does not let a cold key fall over the service that holds
it. The error of the loader reaches every caller that waits for it, and the
value is not cached: the next call tries again.

The value of `remember` is written for the `ttl` of the call, or for the
`defaultTtl` of the cache.

## The lifecycle of the service

A cache that is warmed needs a place to warm it, and a client that is opened
needs a place to close it. The application holds three hooks for that:

```dart
final app = Laska();

app.onStart(() async {
  // The port is not bound yet: the service acquires its resources here.
  await app.cache.remember('report', () async {
    return loadTheReport();
  });
});

app.onReady(() async {
  // The port is bound and the gRPC server is up: the service answers.
  logger.info('the service is ready');
});

app.onShutdown(() async {
  // The requests in flight finished: the service releases its resources.
  await client.close();
});
```

The order of the phases is fixed:

| Phase | When it runs |
|---|---|
| `onStart` | Before the port is bound. A hook that throws keeps the service from starting. |
| `onReady` | When the port is bound and the gRPC server is up. |
| `onShutdown` | After the requests in flight finished, before the socket is closed. |

The hooks of the shutdown phase run after the drain, so the resources they
release are still alive while the last answers are written. A hook that fails
is written to the log and the next hook runs — a resource that fails to close
must not keep the other resources open.

A group holds its own hooks, and they run after the hooks of the application:

```dart
app.onStart(() => logger.info('the service starts'));

app.group('/api', (group) {
  group.onStart(() => logger.info('the api starts'));
});
```

## Write your own store

A store is four methods. The one below keeps the values in Redis:

```dart
class RedisCacheStore implements CacheStore {
  RedisCacheStore(this._client);

  final RedisClient _client;

  @override
  Future<T?> read<T>(String key) async {
    final raw = await _client.get(key);
    if (raw == null) {
      return null;
    }
    return jsonDecode(raw) as T;
  }

  @override
  Future<void> write<T>(String key, T value, {Duration? ttl}) async {
    await _client.set(
      key,
      jsonEncode(value),
      expiry: ttl ?? const Duration(minutes: 5),
    );
  }

  @override
  Future<void> delete(String key) => _client.del(key);

  @override
  Future<void> clear() => _client.flush();
}
```

The service hands the store to the cache and the rest of the service does not
change:

```dart
app.cache = Cache(RedisCacheStore(client));
```

## Test the cache

`laska_test` ships `FakeCacheStore` — a store that keeps the values in memory
and records the calls:

```dart
final store = FakeCacheStore();
app.cache = Cache(store);

final response = await testClient(app).get('/report');

expect(store.reads, contains('report'));
expect(store.hits, 1);
```

The fake fails on demand, so a test covers the service that survives a broken
cache:

```dart
store.error = StateError('the cache is down');
```

## What not to cache

The cache is a tool, not a habit:

- **Cache the answers that are expensive to compute** — a report, a price, a
  picture that is rendered. Not the answers that are cheap to read.
- **Cache the values that change slowly.** A value that changes every second
  spends more time in the cache than in the service.
- **Do not cache the answers that belong to a caller.** The answers of a
  request carry the identity of the caller; they belong to the session, not to
  the cache.
- **Do not cache everything.** A cache without a policy is a copy of the
  database with an expiry date — it holds stale values and hides the queries
  that are slow.
