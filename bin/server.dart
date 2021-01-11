import 'dart:io';

import 'package:laska/laska.dart';

void main(List<String> args) async {

  final app = Laska();

  app.GET('/', (Context context) => context.Text('Hello, world.'));

  app.GET('/todos', (Context context) async {
    throw Exception('Custom Exception throwed.');
  });

  await app.run();
}
