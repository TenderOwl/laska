import 'dart:developer';

import 'package:laska/laska.dart';

void main(List<String> args) async {
  final app = Laska()
    ..get('/', (Context context) => context.text('Hello, world from Laska'));

  app.beforeStartup.subscribe((app) => log('before_startup 1'));
  app.beforeStartup.subscribe((app) => log('before_startup 2'));
  app.afterStartup.subscribe((app) => log('after_startup 1'));
  app.afterStartup.subscribe((app) => log('after_startup 2'));

  app.beforeTeardown.subscribe((app) => log('before_teardown 1'));
  app.beforeTeardown.subscribe((app) => log('before_teardown 2'));
  app.afterTeardown.subscribe((app) => log('after_teardown 1'));
  app.afterTeardown.subscribe((app) => log('after_teardown 2'));

  await run(app);
}
