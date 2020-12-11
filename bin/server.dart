import 'dart:io';

import 'package:laska/laska.dart';

void main() async {
  // Create new Laska object with 2 [Isolate]
  final laska = Laska(isolateCount: 2);

  laska.GET('/users/:userId', getUserById);
  laska.POST('/users/', createUser);

  // Start server
  await run(laska);
}

void getUserById(HttpRequest request, {String userId}) async {
  request.response.write('User($userId)');
}

void createUser(HttpRequest request, {String userId}) async {
  request.response.statusCode = HttpStatus.created;
  request.response.write('New user created');
}