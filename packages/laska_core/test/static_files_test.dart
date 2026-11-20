import 'dart:convert';
import 'dart:io';

import 'package:laska_core/laska_core.dart';
import 'package:test/test.dart';

Request _request(
  String method,
  String path, {
  Map<String, String>? headers,
}) {
  final uri = Uri.parse(path);
  return Request(
    method: method,
    path: uri.path,
    uri: path,
    query: uri.queryParameters,
    headers: headers ?? const <String, String>{},
  );
}

Request _rawRequest(
  String method,
  String path, {
  Map<String, String>? headers,
}) =>
    Request(
      method: method,
      path: path,
      uri: path,
      query: const <String, String>{},
      headers: headers ?? const <String, String>{},
    );

void main() {
  late Directory directory;

  setUp(() {
    directory = Directory.systemTemp.createTempSync('laska_static_');
  });

  tearDown(() {
    if (directory.existsSync()) {
      directory.deleteSync(recursive: true);
    }
  });

  File _write(String path, String content) {
    final file = File('${directory.path}${Platform.pathSeparator}$path');
    file.parent.createSync(recursive: true);
    file.writeAsStringSync(content);
    return file;
  }

  group('Static files', () {
    test('serves a file of the directory', () async {
      _write('app.js', 'console.log(1);');
      final app = Laska();
      app.staticFiles('/assets', directory.path);

      final response =
          await app.dispatcher.dispatch(_request('GET', '/assets/app.js'));

      expect(response.status, 200);
      expect(response.text, 'console.log(1);');
      expect(
          response.headers['content-type'], 'text/javascript; charset=utf-8');
    });

    test('serves a file of a subdirectory', () async {
      _write('css/main.css', 'body {}');
      final app = Laska();
      app.staticFiles('/assets', directory.path);

      final response = await app.dispatcher
          .dispatch(_request('GET', '/assets/css/main.css'));

      expect(response.status, 200);
      expect(response.text, 'body {}');
      expect(response.headers['content-type'], 'text/css; charset=utf-8');
    });

    test('serves the files of the root of the application', () async {
      _write('index.html', '<h1>Laska</h1>');
      final app = Laska();
      app.staticFiles('/', directory.path);

      final response =
          await app.dispatcher.dispatch(_request('GET', '/index.html'));

      expect(response.status, 200);
      expect(response.text, '<h1>Laska</h1>');
    });

    test('serves the files of a group', () async {
      _write('app.js', 'console.log(1);');
      final app = Laska();
      app.group('/admin', (group) {
        group.staticFiles('/assets', directory.path);
      });

      final response = await app.dispatcher
          .dispatch(_request('GET', '/admin/assets/app.js'));

      expect(response.status, 200);
      expect(response.text, 'console.log(1);');
    });

    test('serves the index file when the request points at a directory',
        () async {
      _write('index.html', '<h1>Laska</h1>');
      final app = Laska();
      app.staticFiles('/assets', directory.path);

      final response =
          await app.dispatcher.dispatch(_request('GET', '/assets'));

      expect(response.status, 200);
      expect(response.text, '<h1>Laska</h1>');
    });

    test('answers 404 with a problem document when the file is missing',
        () async {
      final app = Laska();
      app.staticFiles('/assets', directory.path);

      final response =
          await app.dispatcher.dispatch(_request('GET', '/assets/nope.js'));

      expect(response.status, 404);
      expect(response.headers['content-type'],
          contains('application/problem+json'));
      expect(response.jsonObject['title'], 'Not Found');
    });

    test('serves the fallback file when the file is missing', () async {
      _write('index.html', '<h1>Laska</h1>');
      final app = Laska();
      app.staticFiles('/assets', directory.path, fallback: 'index.html');

      final response =
          await app.dispatcher.dispatch(_request('GET', '/assets/admin/users'));

      expect(response.status, 200);
      expect(response.text, '<h1>Laska</h1>');
      expect(response.headers['content-type'], 'text/html; charset=utf-8');
    });

    test('refuses a path that points outside of the directory', () async {
      _write('secret.txt', 'secret');
      final app = Laska();
      app.staticFiles('/assets', directory.path);

      final response = await app.dispatcher
          .dispatch(_request('GET', '/assets/../secret.txt'));

      expect(response.status, 404);
    });

    test('refuses an encoded path that points outside of the directory',
        () async {
      _write('secret.txt', 'secret');
      final app = Laska();
      app.staticFiles('/assets', directory.path);

      final response = await app.dispatcher
          .dispatch(_request('GET', '/assets/%2e%2e/secret.txt'));

      expect(response.status, 404);
    });

    test('decodes the path of the file', () async {
      _write('my file.txt', 'hello');
      final app = Laska();
      app.staticFiles('/assets', directory.path);

      final response = await app.dispatcher
          .dispatch(_request('GET', '/assets/my%20file.txt'));

      expect(response.status, 200);
      expect(response.text, 'hello');
    });

    test('decodes a path of a file with a non-latin name', () async {
      _write('привет.txt', 'hello');
      final app = Laska();
      app.staticFiles('/assets', directory.path);

      final response = await app.dispatcher.dispatch(
        _request('GET', '/assets/%D0%BF%D1%80%D0%B8%D0%B2%D0%B5%D1%82.txt'),
      );

      expect(response.status, 200);
      expect(response.text, 'hello');
    });

    test('answers 400 when the path is not encoded correctly', () async {
      final app = Laska();
      app.staticFiles('/assets', directory.path);

      final response =
          await app.dispatcher.dispatch(_rawRequest('GET', '/assets/%zz'));

      expect(response.status, 400);
      expect(response.jsonObject['title'], 'Bad Request');
    });

    test('serves a file of an unknown extension as a binary one', () async {
      _write('data.bin', 'binary');
      final app = Laska();
      app.staticFiles('/assets', directory.path);

      final response =
          await app.dispatcher.dispatch(_request('GET', '/assets/data.bin'));

      expect(response.status, 200);
      expect(response.headers['content-type'], 'application/octet-stream');
    });

    test('writes the validators of the cache', () async {
      _write('app.js', 'console.log(1);');
      final app = Laska();
      app.staticFiles('/assets', directory.path);

      final response =
          await app.dispatcher.dispatch(_request('GET', '/assets/app.js'));

      expect(response.headers['etag'], isNotEmpty);
      expect(response.headers['last-modified'], isNotEmpty);
      expect(response.headers['x-content-type-options'], 'nosniff');
    });

    test('writes the cache control when the age is given', () async {
      _write('app.js', 'console.log(1);');
      final app = Laska();
      app.staticFiles(
        '/assets',
        directory.path,
        maxAge: const Duration(hours: 1),
      );

      final response =
          await app.dispatcher.dispatch(_request('GET', '/assets/app.js'));

      expect(response.headers['cache-control'], 'public, max-age=3600');
    });

    test('answers 304 when the client holds the file', () async {
      _write('app.js', 'console.log(1);');
      final app = Laska();
      app.staticFiles('/assets', directory.path);

      final first =
          await app.dispatcher.dispatch(_request('GET', '/assets/app.js'));
      final etag = first.headers['etag']!;

      final response = await app.dispatcher.dispatch(
        _request('GET', '/assets/app.js', headers: <String, String>{
          'if-none-match': etag,
        }),
      );

      expect(response.status, 304);
      expect(response.body, isEmpty);
      expect(response.headers['etag'], etag);
    });

    test('answers 304 when the file was not changed since', () async {
      _write('app.js', 'console.log(1);');
      final app = Laska();
      app.staticFiles('/assets', directory.path);

      final first =
          await app.dispatcher.dispatch(_request('GET', '/assets/app.js'));
      final lastModified = first.headers['last-modified']!;

      final response = await app.dispatcher.dispatch(
        _request('GET', '/assets/app.js', headers: <String, String>{
          'if-modified-since': lastModified,
        }),
      );

      expect(response.status, 304);
      expect(response.body, isEmpty);
    });

    test('serves the file when the validator of the client is old', () async {
      _write('app.js', 'console.log(1);');
      final app = Laska();
      app.staticFiles('/assets', directory.path);

      final response = await app.dispatcher.dispatch(
        _request('GET', '/assets/app.js', headers: <String, String>{
          'if-none-match': '"stale"',
        }),
      );

      expect(response.status, 200);
      expect(response.text, 'console.log(1);');
    });

    test('answers a HEAD request without a body', () async {
      _write('app.js', 'console.log(1);');
      final app = Laska();
      app.staticFiles('/assets', directory.path);

      final response =
          await app.dispatcher.dispatch(_request('HEAD', '/assets/app.js'));

      expect(response.status, 200);
      expect(response.body, isEmpty);
      expect(response.headers['content-length'], '15');
      expect(
          response.headers['content-type'], 'text/javascript; charset=utf-8');
    });

    test('does not shadow a route that is more specific', () async {
      _write('api', 'the file');
      final app = Laska();
      app.staticFiles('/assets', directory.path);
      app.get('/assets/api', (ctx) => ctx.text('the route'));

      final response =
          await app.dispatcher.dispatch(_request('GET', '/assets/api'));

      expect(response.status, 200);
      expect(response.text, 'the route');
    });

    test('writes the extra headers of the registration', () async {
      _write('app.js', 'console.log(1);');
      final app = Laska();
      app.staticFiles(
        '/assets',
        directory.path,
        headers: <String, String>{'x-frame-options': 'DENY'},
      );

      final response =
          await app.dispatcher.dispatch(_request('GET', '/assets/app.js'));

      expect(response.headers['x-frame-options'], 'DENY');
    });
  });

  group('HTML', () {
    test('builds an HTML response', () {
      final response = Response.html('<h1>Laska</h1>');

      expect(response.status, 200);
      expect(response.headers['content-type'], 'text/html; charset=utf-8');
      expect(response.text, '<h1>Laska</h1>');
    });

    test('the handler builds an HTML response', () async {
      final app = Laska();
      app.get('/', (ctx) => ctx.html('<h1>Laska</h1>'));

      final response = await app.dispatcher.dispatch(_request('GET', '/'));

      expect(response.status, 200);
      expect(response.headers['content-type'], 'text/html; charset=utf-8');
      expect(response.text, '<h1>Laska</h1>');
    });

    test('the handler builds an HTML response with a status', () async {
      final app = Laska();
      app.get('/', (ctx) => ctx.html('<h1>Missing</h1>', status: 404));

      final response = await app.dispatcher.dispatch(_request('GET', '/'));

      expect(response.status, 404);
      expect(response.headers['content-type'], 'text/html; charset=utf-8');
    });
  });

  group('Static files over HTTP', () {
    late HttpServer server;

    setUp(() async {
      _write('app.js', 'console.log(1);');
      final app = Laska();
      app.staticFiles('/assets', directory.path);
      server = await serve(app, port: 0);
    });

    tearDown(() async {
      await server.close(force: true);
    });

    test('serves the file with its type', () async {
      final client = HttpClient();
      final request = await client
          .getUrl(Uri.parse('http://127.0.0.1:${server.port}/assets/app.js'));
      final response = await request.close();
      final body = await response.transform(utf8.decoder).join();
      client.close();

      expect(response.statusCode, 200);
      expect(response.headers.contentType?.mimeType, 'text/javascript');
      expect(response.headers.contentType?.charset, 'utf-8');
      expect(body, 'console.log(1);');
    });

    test('answers a HEAD request with the length of the file', () async {
      final client = HttpClient();
      final request = await client
          .headUrl(Uri.parse('http://127.0.0.1:${server.port}/assets/app.js'));
      final response = await request.close();
      await response.drain<void>();
      client.close();

      expect(response.statusCode, 200);
      expect(response.headers.value('content-length'), '15');
    });

    test('answers 304 when the client holds the file', () async {
      final client = HttpClient();

      final first = await client
          .getUrl(Uri.parse('http://127.0.0.1:${server.port}/assets/app.js'));
      final firstResponse = await first.close();
      await firstResponse.drain<void>();
      final etag = firstResponse.headers.value('etag')!;

      final request = await client
          .getUrl(Uri.parse('http://127.0.0.1:${server.port}/assets/app.js'));
      request.headers.set('if-none-match', etag);
      final response = await request.close();
      final body = await response.transform(utf8.decoder).join();
      client.close();

      expect(response.statusCode, 304);
      expect(body, isEmpty);
    });

    test('answers an unknown file with a problem document', () async {
      final client = HttpClient();
      final request = await client
          .getUrl(Uri.parse('http://127.0.0.1:${server.port}/page'));
      final response = await request.close();
      final body = await response.transform(utf8.decoder).join();
      client.close();

      expect(response.statusCode, 404);
      expect(
          response.headers.contentType?.mimeType, 'application/problem+json');
      expect(body, contains('Not Found'));
    });
  });

  group('HTML over HTTP', () {
    test('serves the page as a document of HTML', () async {
      final app = Laska();
      app.get('/', (ctx) => ctx.html('<h1>Laska</h1>'));
      final server = await serve(app, port: 0);

      final client = HttpClient();
      final request =
          await client.getUrl(Uri.parse('http://127.0.0.1:${server.port}/'));
      final response = await request.close();
      final body = await response.transform(utf8.decoder).join();
      client.close();
      await server.close(force: true);

      expect(response.statusCode, 200);
      expect(response.headers.contentType?.mimeType, 'text/html');
      expect(response.headers.contentType?.charset, 'utf-8');
      expect(body, '<h1>Laska</h1>');
    });
  });

  group('The dates of HTTP', () {
    test('formats a date', () {
      final date = DateTime.utc(1994, 11, 6, 8, 49, 37);

      expect(formatHttpDate(date), 'Sun, 06 Nov 1994 08:49:37 GMT');
    });

    test('reads a date of the format of RFC 9110', () {
      final date = parseHttpDate('Sun, 06 Nov 1994 08:49:37 GMT');

      expect(date, DateTime.utc(1994, 11, 6, 8, 49, 37));
    });

    test('reads a date of the format of RFC 850', () {
      final date = parseHttpDate('Sunday, 06-Nov-94 08:49:37 GMT');

      expect(date, DateTime.utc(1994, 11, 6, 8, 49, 37));
    });

    test('reads a date of the format of asctime', () {
      final date = parseHttpDate('Sun Nov  6 08:49:37 1994');

      expect(date, DateTime.utc(1994, 11, 6, 8, 49, 37));
    });

    test('refuses a value that is not a date', () {
      expect(parseHttpDate('yesterday'), isNull);
    });
  });
}
