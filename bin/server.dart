import 'package:laska/laska.dart';

void main(List<String> args) async {
  final app = Laska()
    ..GET('/', (context) => context.Text('Hello, world.'));

  await app.run();
}
