import 'package:admin_app/app.dart';
import 'package:laska_core/laska_core.dart';
import 'package:laska_test/laska_test.dart';
import 'package:shop_gateway_service/generated/shop_gateway.pb.dart';
import 'package:test/test.dart';

void main() {
  group('the app of the workspace', () {
    test('serves the frontend', () async {
      final app = Laska();
      registerApp(app);

      final client = testClient(app);

      final response = await client.get('/');
      response.expectStatus(200);
      expect(response.body, contains('<h1>Admin</h1>'));
    });

    test('forwards the call to the service behind it', () async {
      final transport = TestTransport();
      transport.enqueueResponse(
        200,
        body: <String, Object?>{'id': 'u_1', 'name': 'A record'},
      );

      final app = Laska();
      registerApp(
        app,
        shopGateway: ShopGatewayServiceClient(
          baseUrl: 'http://localhost:8081',
          transport: transport,
        ),
      );

      final client = testClient(app);

      final response = await client.get(
        '/v1/shop_gateway/u_1',
        headers: <String, String>{
          'authorization': 'Bearer the-token',
        },
      );
      response.expectStatus(200);

      // The call reached the service behind the app, and the headers of the
      // caller travelled with it.
      expect(transport.requests, hasLength(1));
      expect(
        transport.requests.first.headers['authorization'],
        'Bearer the-token',
      );
    });
  });
}
