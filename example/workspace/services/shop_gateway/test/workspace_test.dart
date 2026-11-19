import 'dart:io';

import 'package:laska_core/laska_core.dart';
import 'package:laska_test/laska_test.dart';
import 'package:shop_gateway_service/generated/shop_gateway.pb.dart';
import 'package:shop_gateway_service/shop_gateway_service.dart';
import 'package:shop_service/generated/shop.pb.dart';
import 'package:shop_service/shop_service.dart';
import 'package:test/test.dart';

void main() {
  group('the workspace of two services', () {
    late HttpServer shopServer;
    late Laska gatewayApp;
    late TestTracer tracer;

    setUp(() async {
      tracer = TestTracer();

      // The service that keeps the records.
      final shopApp = Laska();
      await Observability.install(shopApp, tracer: tracer);
      registerShopService(shopApp, ShopServiceImpl());
      shopServer = await serve(shopApp, port: 0);

      // The service that calls it through the client of its contract.
      gatewayApp = Laska();
      await Observability.install(gatewayApp, tracer: tracer);
      registerShopGatewayService(
        gatewayApp,
        ShopGatewayServiceImpl(
          shop: ShopServiceClient(
            baseUrl: 'http://127.0.0.1:${shopServer.port}',
            tracer: tracer,
          ),
        ),
      );
    });

    tearDown(() async {
      await shopServer.close(force: true);
    });

    test('the gateway answers with the record of the service behind it',
        () async {
      final client = testClient(gatewayApp);

      final response = await client.get('/v1/shop_gateway/u_1');
      response.expectStatus(200);

      final body = response.json as Map<String, dynamic>;
      expect(body['id'], 'u_1');
      expect(body['name'], 'A record');
    });

    test('the record that is not there is reported as a problem document',
        () async {
      final client = testClient(gatewayApp);

      final response = await client.get('/v1/shop_gateway/missing');
      response.expectStatus(404);
    });

    test('the call to the service behind belongs to the trace of the request',
        () async {
      final client = testClient(gatewayApp);
      await client.get('/v1/shop_gateway/u_1');

      // The client of the contract writes the trace of the request into the
      // header of the call, and the service behind continues that trace: the
      // two services answer with one trace.
      final clientSpan = tracer.spansNamed('ShopService.GetShop').single;
      expect(clientSpan.kind, SpanKind.client);

      final serverSpans = tracer.spansNamed('http.server');
      expect(serverSpans, hasLength(2));

      final traceIds = tracer.spans.map((span) => span.context.traceId).toSet();
      expect(traceIds, hasLength(1));
    });
  });
}
