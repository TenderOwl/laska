import 'package:laska_core/laska_core.dart';

/// A service used by the CLI tests.
///
/// The `laska route:list` command runs it with a flag, so it prints its route
/// table and exits.
Future<void> main(List<String> arguments) async {
  final app = Laska();

  app.get('/users', (ctx) => ctx.text('ok'), name: 'users');
  app.get('/users/:id<int>', (ctx) => ctx.text(ctx.params['id']!));
  app.post('/users', (ctx) => ctx.text('created'), name: 'createUser');

  await run(app, arguments: arguments);
}
