import 'package:admin_app/app.dart';
import 'package:laska_core/laska_core.dart';

Future<void> main(List<String> arguments) async {
  final app = Laska();

  await Observability.install(
    app,
    logger: Logger(service: 'admin', version: '0.1.0'),
  );

  registerApp(app);

  await run(app, arguments: arguments);
}
