import 'package:laska_core/laska_core.dart';
import 'package:test/test.dart';

void main() {
  group('the memory store', () {
    test('writes and reads a value', () async {
      final store = MemoryCacheStore();

      await store.write('greeting', 'hello');

      expect(await store.read<String>('greeting'), 'hello');
      expect(store.length, 1);
    });

    test('reads a missing key as null', () async {
      final store = MemoryCacheStore();

      expect(await store.read<String>('greeting'), isNull);
    });

    test('reads a value of another type as null', () async {
      final store = MemoryCacheStore();
      await store.write('greeting', 'hello');

      expect(await store.read<int>('greeting'), isNull);
    });

    test('forgets a value when its ttl is over', () async {
      var now = DateTime(2026);
      final store = MemoryCacheStore(clock: () => now);

      await store.write('greeting', 'hello', ttl: const Duration(minutes: 5));
      expect(await store.read<String>('greeting'), 'hello');

      now = now.add(const Duration(minutes: 5));

      expect(await store.read<String>('greeting'), isNull);
      expect(store.length, 0);
    });

    test('keeps a value without a ttl', () async {
      var now = DateTime(2026);
      final store = MemoryCacheStore(clock: () => now);

      await store.write('greeting', 'hello');
      now = now.add(const Duration(days: 365));

      expect(await store.read<String>('greeting'), 'hello');
    });

    test('forgets the least recently used value when it grows', () async {
      final store = MemoryCacheStore(maxEntries: 2);

      await store.write('a', 1);
      await store.write('b', 2);
      await store.write('c', 3);

      expect(store.keys, <String>['b', 'c']);
      expect(await store.read<int>('a'), isNull);
      expect(await store.read<int>('b'), 2);
    });

    test('keeps the value that was read recently', () async {
      final store = MemoryCacheStore(maxEntries: 2);

      await store.write('a', 1);
      await store.write('b', 2);
      await store.read<int>('a');
      await store.write('c', 3);

      expect(store.keys, <String>['a', 'c']);
      expect(await store.read<int>('a'), 1);
    });

    test('deletes and clears the values', () async {
      final store = MemoryCacheStore();
      await store.write('a', 1);
      await store.write('b', 2);

      await store.delete('a');
      expect(await store.read<int>('a'), isNull);
      expect(store.length, 1);

      await store.clear();
      expect(store.length, 0);
    });

    test('refuses a limit that is not positive', () {
      expect(
        () => MemoryCacheStore(maxEntries: 0),
        throwsArgumentError,
      );
    });
  });

  group('the cache', () {
    test('puts and gets a value', () async {
      final cache = Cache.memory();

      await cache.put('greeting', 'hello');

      expect(await cache.get<String>('greeting'), 'hello');
    });

    test('gives a value the default ttl', () async {
      var now = DateTime(2026);
      final store = MemoryCacheStore(clock: () => now);
      final cache = Cache(store, defaultTtl: const Duration(minutes: 1));

      await cache.put('greeting', 'hello');
      expect(await cache.get<String>('greeting'), 'hello');

      now = now.add(const Duration(minutes: 1));

      expect(await cache.get<String>('greeting'), isNull);
    });

    test('removes a value and clears the cache', () async {
      final cache = Cache.memory();
      await cache.put('greeting', 'hello');

      await cache.delete('greeting');
      expect(await cache.get<String>('greeting'), isNull);

      await cache.put('greeting', 'hello');
      await cache.clear();
      expect(await cache.get<String>('greeting'), isNull);
    });

    test('remembers a value and loads it once', () async {
      final cache = Cache.memory();
      var loads = 0;

      Future<int> loader() async {
        loads++;
        return 42;
      }

      expect(await cache.remember('answer', loader), 42);
      expect(await cache.remember('answer', loader), 42);
      expect(loads, 1);
    });

    test('loads a value once for a burst of calls', () async {
      final cache = Cache.memory();
      var loads = 0;

      Future<int> loader() async {
        loads++;
        await Future<void>.delayed(const Duration(milliseconds: 20));
        return 42;
      }

      final values = await Future.wait<int>(<Future<int>>[
        cache.remember('answer', loader),
        cache.remember('answer', loader),
        cache.remember('answer', loader),
      ]);

      expect(values, everyElement(42));
      expect(loads, 1);
      expect(cache.pending, 0);
    });

    test('does not cache the error of the loader', () async {
      final cache = Cache.memory();
      var loads = 0;

      Future<int> loader() async {
        loads++;
        throw StateError('the loader failed');
      }

      await expectLater(cache.remember('answer', loader), throwsStateError);
      await expectLater(cache.remember('answer', loader), throwsStateError);
      expect(loads, 2);
      expect(cache.pending, 0);
    });

    test('keeps the values of the store it was given', () async {
      final store = MemoryCacheStore();
      final cache = Cache(store);

      await cache.put('greeting', 'hello', ttl: const Duration(minutes: 1));

      expect(await store.read<String>('greeting'), 'hello');
    });
  });

  group('the cache of the application', () {
    test('is a memory cache by default', () {
      final app = Laska();

      expect(app.cache, isA<Cache>());
      expect(app.cache.store, isA<MemoryCacheStore>());
    });

    test('is inherited by the groups', () {
      final app = Laska();
      late Laska group;
      app.group('/api', (child) {
        group = child;
      });

      final cache = Cache.memory();
      app.cache = cache;

      expect(group.cache, same(cache));
    });

    test('follows the cache the application was given', () {
      final app = Laska();
      late Laska group;
      app.group('/api', (child) {
        group = child;
      });

      expect(group.cache, same(app.cache));

      final cache = Cache.memory();
      app.cache = cache;

      expect(group.cache, same(cache));
    });
  });
}
