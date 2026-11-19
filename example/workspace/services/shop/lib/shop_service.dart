import 'package:laska_core/laska_core.dart';

import 'generated/shop.pb.dart';

/// The implementation of the ShopService service.
class ShopServiceImpl implements ShopService {
  final Map<String, Shop> _records = <String, Shop>{
    // One record, so the service answers something on the first call. Replace
    // the map with the table of your database.
    'u_1': Shop(id: 'u_1', name: 'A record'),
  };

  @override
  Future<Shop> getShop(GetShopRequest request) async {
    final record = _records[request.id];
    if (record == null) {
      throw HttpException(
        404,
        'Shop "${request.id}" was not found',
        code: 'not_found',
      );
    }
    return record;
  }
}
