import 'package:laska_core/laska_core.dart';
import 'package:laska_test/laska_test.dart';
import 'package:test/test.dart';

import 'package:shop_service/generated/shop.pb.dart';
import 'package:shop_service/shop_service.dart';

void main() {
  test('the service answers with the record it keeps', () async {
    final app = Laska();
    registerShopService(app, ShopServiceImpl());

    final client = testClient(app);

    final response = await client.get('/v1/shop/u_1');
    response.expectStatus(200);
  });

  test('an unknown record is reported as a problem document', () async {
    final app = Laska();
    registerShopService(app, ShopServiceImpl());

    final client = testClient(app);

    final response = await client.get('/v1/shop/missing');
    response.expectStatus(404);
  });
}
