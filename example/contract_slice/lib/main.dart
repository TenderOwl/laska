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

  // The contract of the service is served on both transports: the REST
  // projection on the port of the HTTP server and the methods of the contract
  // on the port of the gRPC server.
  await run(app, arguments: arguments, port: 8080, grpcPort: 50051);
}
