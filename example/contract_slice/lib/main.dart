import 'package:laska_core/laska_core.dart';

import '../generated/users.pb.dart';
import 'service.dart';

/// Starts the example service.
Future<void> main(List<String> arguments) async {
  final app = Laska();
  registerUsersService(app, UsersServiceImpl());

  app.get('/', (ctx) async {
    return ctx.text('Laska is here!');
  });

  await run(app, arguments: arguments, port: 8080);
}
