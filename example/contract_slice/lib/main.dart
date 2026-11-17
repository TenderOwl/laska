import 'package:laska_core/laska_core.dart';

import '../generated/users.pb.dart';
import 'service.dart';

/// Starts the example service.
Future<void> main() async {
  final app = Laska();
  registerUsersService(app, UsersServiceImpl());

  await run(app, port: 8080);
}
