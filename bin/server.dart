import 'dart:io';

import 'package:laska/laska.dart';

void main() async {
  final laska = Laska();

  laska.GET('/users/:userId', (request, {dynamic userId}) {
    request.response.write('GET: ${request.uri.path} |> $userId [$userId.runtimeType]');
  });

  laska.GET('/users/new', (request) {
    request.response.write('GET: ${request.uri.path}');
  });

  laska.POST('/users/1/files/*', (request) {
    request.response.write('POST: ${request.uri.path}');
  });

  laska.GET('/users/:userId/edit', authHandler);

  await laska.run();
}

void authHandler(HttpRequest request, {String userId}) async {
  request.response.write('authHandler: ${request.uri.path} |> $userId');
}
