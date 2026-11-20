import 'dart:io';

import 'package:admin_app/app.dart';
import 'package:laska_core/laska_core.dart';
import 'package:laska_test/laska_test.dart';
import 'package:shop_gateway_service/generated/shop_gateway.pb.dart';
import 'package:test/test.dart';

void main() {
  group('the app of the workspace', () {
    test('serves the frontend', () async {
      final app = Laska();
      await registerApp(app);

      final client = testClient(app);

      final response = await client.get('/');
      response.expectStatus(200);
      expect(response.body, contains('<h1>Admin</h1>'));
    });

    test('serves the frontend from any directory', () async {
      // The files of the frontend live in the package of the app, so the app
      // serves them no matter the directory the process was started in.
      final elsewhere = Directory.systemTemp.createTempSync('laska_app_cwd');
      final current = Directory.current.path;
      Directory.current = elsewhere.path;

      try {
        final app = Laska();
        await registerApp(app);

        final client = testClient(app);

        final response = await client.get('/');
        response.expectStatus(200);
        expect(response.body, contains('<h1>Admin</h1>'));
      } finally {
        Directory.current = current;
        if (elsewhere.existsSync()) {
          elsewhere.deleteSync(recursive: true);
        }
      }
    });

    test('forwards the call to the service behind it', () async {
      final transport = TestTransport();
      transport.enqueueResponse(
        200,
        body: <String, Object?>{'id': 'u_1', 'name': 'A record'},
      );

      final app = Laska();
      await registerApp(
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
