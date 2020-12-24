import 'dart:io';

import 'package:laska/laska.dart';


void main() async {
  // Create new Laska object with 2 [Isolate]
  final laska = Laska(isolateCount: 1);

  laska.Use(BasicAuth('laska', 'ermine', realm: 'Access to private zone'));

  laska.GET('/users/:userId', getUserById);
  laska.POST('/users/', createUser);

  // Start server
  await run(laska);
}

void getUserById(Context context) async {
  await context.HTML('<p>User: <b>${context.params['userId']}</b></p>');
}

void createUser(Context context) async {
  await context.JSON({'status': 'created'}, statusCode: HttpStatus.created);
}
