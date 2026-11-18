import 'package:laska_core/laska_core.dart';

import 'app.dart';
import 'keys.dart';

/// Starts the example service.
///
/// The service listens on the port 8080, and the routes of the example are
/// listed by `laska --help` of the framework:
///
/// - `POST /login` gives a token to the caller that knows the name and the
///   password;
/// - `POST /session` gives a session to the browser;
/// - `GET /me` needs the token;
/// - `GET /admin` needs the token with the scope `admin`;
/// - `GET /machine` needs the API key of the machine;
/// - `GET /session` needs the session of the browser.
Future<void> main(List<String> arguments) async {
  final app = await buildApp(
    keys: ServiceKeys.development(),
    limiter: RateLimiter(limit: 100, window: const Duration(minutes: 1)),
  );

  await run(app, arguments: arguments, port: 8080);
}
