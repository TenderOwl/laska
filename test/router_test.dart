import 'package:laska/laska.dart';
import 'package:test/test.dart';

void main() {
  late Router router;

  setUp(() {
    router = Router();
    router.get('/static', () {});
    router.get('/dynamic/:key', () {});
    router.get('/multilevel/:key/dynamic/:item', () {});
    router.get('/wild/*', () {});
    router.get('/кириллический/путь', () {});
    router.post('/post', () {});
    router.put('/put', () {});
    router.patch('/patch', () {});
    router.delete('/delete', () {});
    router.insert('HEAD', '/custom', () {});
  });

  test('Static routes found', () {
    expect(router.lookup('/static'), isNotNull);
  });

  test('Dynamic routes found', () {
    expect(router.lookup('/dynamic/31337'), isNotNull);
    expect(router.lookup('/dynamic/elite'), isNotNull);
  });

  test('Dynamic multilevel routes found', () {
    expect(router.lookup('/multilevel/container/dynamic/option-1'), isNotNull);
    expect(router.lookup('/multilevel/container/dynamic/item2'), isNotNull);
  });

  test('wildcard route found', () {
    expect(router.lookup('/wild/card/route'), isNotNull);
  });

  test('Expect to miss route', () {
    expect(router.lookup('/missed-route'), isNull);
  });

  test('Non-ASCII characters are allowed', () {
    expect(router.lookup('/кириллический/путь'), isNotNull);
  });

  test('POST method route found', () {
    expect(router.lookup('/post')?.handlers.containsKey('POST'), isTrue);
  });

  test('PUT method route found', () {
    expect(router.lookup('/put')?.handlers.containsKey('PUT'), isTrue);
  });

  test('PATCH method route found', () {
    expect(router.lookup('/patch')?.handlers.containsKey('PATCH'), isTrue);
  });

  test('DELETE method route found', () {
    expect(router.lookup('/delete')?.handlers.containsKey('DELETE'), isTrue);
  });

  test('Custom method (HEAD) route found', () {
    expect(router.lookup('/custom')?.handlers.containsKey('HEAD'), isTrue);
  });
}
