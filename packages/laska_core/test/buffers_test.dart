import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:laska_core/laska_core.dart';
import 'package:test/test.dart';

void main() {
  group('BufferPool', () {
    test('gives the buffer it holds back', () {
      final pool = BufferPool();
      final buffer = pool.take(128);

      expect(buffer.length, greaterThanOrEqualTo(128));
      expect(pool.length, 0);

      pool.give(buffer);

      expect(pool.length, 1);
      expect(identical(pool.take(64), buffer), isTrue);
    });

    test('builds a buffer when the pool is empty', () {
      final pool = BufferPool();

      final buffer = pool.take(32);

      expect(buffer.length, greaterThanOrEqualTo(32));
    });

    test('drops a buffer that is too big', () {
      final pool = BufferPool(maxSize: 1024);

      pool.give(Uint8List(2048));

      expect(pool.length, 0);
    });

    test('keeps at most the number of buffers it may hold', () {
      final pool = BufferPool(maxBuffers: 2);

      pool.give(Uint8List(64));
      pool.give(Uint8List(64));
      pool.give(Uint8List(64));

      expect(pool.length, 2);
    });
  });

  group('BodyBuffer', () {
    test('reads the bytes of the body', () {
      final pool = BufferPool();
      final buffer = BodyBuffer(pool);

      buffer.add(<int>[1, 2, 3]);
      buffer.add(<int>[4, 5]);

      expect(buffer.length, 5);
      expect(buffer.take(), <int>[1, 2, 3, 4, 5]);
    });

    test('grows when the body is bigger than the buffer', () {
      final pool = BufferPool();
      final buffer = BodyBuffer(pool);

      buffer.add(<int>[1, 2, 3]);
      buffer.add(List<int>.filled(100, 7));

      final bytes = buffer.take();

      expect(bytes.length, 103);
      expect(bytes.sublist(3), List<int>.filled(100, 7));
    });

    test('gives the buffer back to the pool', () {
      final pool = BufferPool();
      final buffer = BodyBuffer(pool);

      buffer.add(<int>[1, 2, 3]);
      buffer.take();
      buffer.release();

      expect(pool.length, 1);
    });

    test('an empty body holds nothing', () {
      final pool = BufferPool();
      final buffer = BodyBuffer(pool);

      expect(buffer.length, 0);
      expect(buffer.take(), isEmpty);
    });
  });

  group('the server', () {
    test('reads the body of a request', () async {
      final app = Laska();
      app.post('/users', (ctx) => ctx.text(ctx.request.body));

      final server = await serve(app);
      final client = HttpClient();
      try {
        final request = await client.postUrl(
          Uri.parse('http://127.0.0.1:${server.port}/users'),
        );
        request.headers.contentType = ContentType.json;
        request.write('{"name":"A record"}');
        final response = await request.close();
        final body = await response.transform(utf8.decoder).join();

        expect(response.statusCode, 200);
        expect(body, '{"name":"A record"}');
      } finally {
        client.close(force: true);
        await server.close(force: true);
      }
    });

    test('reads a body that is bigger than one chunk', () async {
      final app = Laska();
      app.post('/users', (ctx) => ctx.text('${ctx.request.body.length}'));

      final server = await serve(app);
      final client = HttpClient();
      try {
        final request = await client.postUrl(
          Uri.parse('http://127.0.0.1:${server.port}/users'),
        );
        request.write('x' * 100000);
        final response = await request.close();
        final body = await response.transform(utf8.decoder).join();

        expect(response.statusCode, 200);
        expect(body, '100000');
      } finally {
        client.close(force: true);
        await server.close(force: true);
      }
    });
  });
}
