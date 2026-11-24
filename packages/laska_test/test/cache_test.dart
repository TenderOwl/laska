import 'package:laska_core/laska_core.dart';
import 'package:laska_test/laska_test.dart';
import 'package:test/test.dart';

void main() {
  group('the fake store', () {
    test('records the calls of the service', () async {
      final store = FakeCacheStore();

      await store.write('greeting', 'hello', ttl: const Duration(minutes: 1));
      expect(await store.read<String>('greeting'), 'hello');
      await store.read<String>('missing');
      await store.delete('greeting');
      await store.clear();

      expect(store.writes, <String>['greeting']);
      expect(store.reads, <String>['greeting', 'missing']);
      expect(store.deletes, <String>['greeting']);
      expect(store.clears, 1);
      expect(store.hits, 1);
      expect(store.misses, 1);
      expect(store.ttls['greeting'], const Duration(minutes: 1));
    });

    test('fails when the error is set', () async {
      final store = FakeCacheStore()..error = StateError('the cache failed');

      await expectLater(store.read<String>('greeting'), throwsStateError);
      await expectLater(
        store.write<String>('greeting', 'hello'),
        throwsStateError,
      );
    });

    test('holds the values it was given', () {
      final store = FakeCacheStore(values: <String, Object?>{'a': 1});

      expect(store.values, <String, Object?>{'a': 1});
    });
  });

  group('the cache of the service', () {
    test('caches the value of a route', () async {
      final store = FakeCacheStore();
      final app = Laska();
      app.cache = Cache(store);
      var loads = 0;

      app.get('/report', (ctx) async {
        final report = await ctx.app.cache.remember('report', () async {
          loads++;
          return <String, Object?>{'total': 42};
        });
        return ctx.json(report);
      });

      final first = await app.dispatcher.dispatch(
        Request(
          method: 'GET',
          path: '/report',
          uri: '/report',
          query: const <String, String>{},
          headers: const <String, String>{},
        ),
      );
      final second = await app.dispatcher.dispatch(
        Request(
          method: 'GET',
          path: '/report',
          uri: '/report',
          query: const <String, String>{},
          headers: const <String, String>{},
        ),
      );

      expect(first.status, 200);
      expect(second.status, 200);
      expect(loads, 1);
      expect(store.writes, <String>['report']);
    });
  });
}
