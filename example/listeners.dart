import 'package:laska/laska.dart';

void main(List<String> args) async {
  final app = Laska()
    ..GET('/', (Context context) => context.Text('Hello, world from Laska'));

  app.before_startup.subscribe((app) => print('before_startup 1'));
  app.before_startup.subscribe((app) => print('before_startup 2'));
  app.after_startup.subscribe((app) => print('after_startup 1'));
  app.after_startup.subscribe((app) => print('after_startup 2'));

  app.before_teardown.subscribe((app) => print('before_teardown 1'));
  app.before_teardown.subscribe((app) => print('before_teardown 2'));
  app.after_teardown.subscribe((app) => print('after_teardown 1'));
  app.after_teardown.subscribe((app) => print('after_teardown 2'));

  await app.run();
}
