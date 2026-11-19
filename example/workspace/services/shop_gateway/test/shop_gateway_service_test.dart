import 'package:laska_core/laska_core.dart';
import 'package:laska_test/laska_test.dart';
import 'package:shop_service/generated/shop.pb.dart';
import 'package:test/test.dart';

import 'package:shop_gateway_service/generated/shop_gateway.pb.dart';
import 'package:shop_gateway_service/shop_gateway_service.dart';

void main() {
  test('the service answers with the record of the service behind it',
      () async {
    final transport = TestTransport();
    transport.enqueueResponse(
      200,
      body: <String, Object?>{'id': 'u_1', 'name': 'A record'},
    );

    final tracer = TestTracer();
    final app = Laska();
    await Observability.install(app, tracer: tracer);
    registerShopGatewayService(
      app,
      ShopGatewayServiceImpl(
        shop: ShopServiceClient(
          baseUrl: 'http://localhost:8080',
          transport: transport,
          tracer: tracer,
        ),
      ),
    );

    final client = testClient(app);

    final response = await client.get('/v1/shop_gateway/u_1');
    response.expectStatus(200);

    final body = response.json as Map<String, dynamic>;
    expect(body['id'], 'u_1');
    expect(body['name'], 'A record');
  });

  test('the call to the service behind belongs to the trace of the request',
      () async {
    final transport = TestTransport();
    transport.enqueueResponse(
      200,
      body: <String, Object?>{'id': 'u_1', 'name': 'A record'},
    );

    final tracer = TestTracer();
    final app = Laska();
    await Observability.install(app, tracer: tracer);
    registerShopGatewayService(
      app,
      ShopGatewayServiceImpl(
        shop: ShopServiceClient(
          baseUrl: 'http://localhost:8080',
          transport: transport,
          tracer: tracer,
        ),
      ),
    );

    final client = testClient(app);
    await client.get('/v1/shop_gateway/u_1');

    // The call to the service behind carries the trace of the request, so the
    // two services answer with one trace.
    expect(transport.requests.first.headers['traceparent'], isNotNull);
  });

  test('the status of the service behind becomes the status of this service',
      () async {
    final transport = TestTransport();
    transport
        .enqueueResponse(404, body: <String, Object?>{'code': 'not_found'});

    final tracer = TestTracer();
    final app = Laska();
    await Observability.install(app, tracer: tracer);
    registerShopGatewayService(
      app,
      ShopGatewayServiceImpl(
        shop: ShopServiceClient(
          baseUrl: 'http://localhost:8080',
          transport: transport,
          tracer: tracer,
        ),
      ),
    );

    final client = testClient(app);

    final response = await client.get('/v1/shop_gateway/missing');
    response.expectStatus(404);
  });
}
