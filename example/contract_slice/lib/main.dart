import 'package:laska_core/laska_core.dart';

import '../generated/users.pb.dart';
import 'service.dart';

/// Starts the example service.
Future<void> main(List<String> arguments) async {
  final app = Laska();

  // One call wires the request ids, the tracing, the metrics, the request log
  // and the health probes into the service.
  await Observability.install(
    app,
    logger: Logger(service: 'users', version: '0.1.0'),
  );

  registerUsersService(app, UsersServiceImpl());

  app.get('/', (ctx) async {
    return ctx.text('Laska is here!');
  });

  await run(app, arguments: arguments, port: 8080);
}
