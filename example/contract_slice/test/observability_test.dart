import 'dart:io';

import 'package:contract_slice_example/generated/users.pb.dart';
import 'package:contract_slice_example/service.dart';
import 'package:laska_core/laska_core.dart';
import 'package:laska_test/laska_test.dart';
import 'package:test/test.dart';

void main() {
  group('observability', () {
    late HttpServer server;
    late TestTracer serverTracer;

    setUp(() async {
      serverTracer = TestTracer();

      final app = Laska();
      await Observability.install(app, tracer: serverTracer);
      registerUsersService(app, UsersServiceImpl());

      server = await serve(app, port: 0);
    });

    tearDown(() async {
      await server.close(force: true);
    });

    test('a request through two services is one trace', () async {
      final clientTracer = TestTracer();
      final client = UsersServiceClient(
        baseUrl: 'http://127.0.0.1:${server.port}',
        tracer: clientTracer,
      );

      await client.getUser(const GetUserRequest(id: 'u_1'));

      expect(clientTracer.spans, hasLength(1));
      final clientSpan = clientTracer.lastSpan;
      expect(clientSpan.name, 'UsersService.GetUser');
      expect(clientSpan.kind, SpanKind.client);
      expect(clientSpan.ended, isTrue);

      expect(serverTracer.spans, hasLength(1));
      final serverSpan = serverTracer.lastSpan;
      expect(serverSpan.name, 'http.server');
      expect(serverSpan.kind, SpanKind.server);

      expect(serverSpan.parent, isNotNull);
      expect(serverSpan.parent!.traceId, clientSpan.context.traceId);
      expect(serverSpan.parent!.spanId, clientSpan.context.spanId);
    });

    test('the server records the attributes of the request', () async {
      final client = UsersServiceClient(
        baseUrl: 'http://127.0.0.1:${server.port}',
        tracer: TestTracer(),
      );

      await client.getUser(const GetUserRequest(id: 'u_1'));

      final span = serverTracer.lastSpan;
      expect(span.attributes['http.request.method'], 'GET');
      expect(span.attributes['url.path'], '/v1/users/u_1');
      expect(span.attributes['http.response.status_code'], 200);
    });

    test('the health probes answer', () async {
      final client = HttpClient();

      final health = await client.getUrl(
        Uri.parse('http://127.0.0.1:${server.port}/healthz'),
      );
      final healthResponse = await health.close();

      final ready = await client.getUrl(
        Uri.parse('http://127.0.0.1:${server.port}/readyz'),
      );
      final readyResponse = await ready.close();

      expect(healthResponse.statusCode, 200);
      expect(readyResponse.statusCode, 200);
      client.close();
    });

    test('the metrics endpoint exposes the requests', () async {
      final client = HttpClient();
      final request = await client.getUrl(
        Uri.parse('http://127.0.0.1:${server.port}/metrics'),
      );
      final response = await request.close();
      final body = await response.transform(SystemEncoding().decoder).join();
      client.close();

      expect(response.statusCode, 200);
      expect(body, contains('laska_http_requests_total'));
    });
  });
}
