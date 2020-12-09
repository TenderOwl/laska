# Laska

## Microframework for web development for Dart

Currently, in development, not for production use.

## Example

```dart
import 'dart:io';

import 'package:laska/laska.dart';

void main() async {
    final laska = Laska();
    
    laska.GET('/users/:userId', userHandler);
    
    laska.GET('/users/new', (request) {
        request.response.write('GET: ${request.uri.path}');
    });
    
    laska.POST('/users/1/files/*', (request) {
        request.response.write('POST: ${request.uri.path}');
    });
    
    await laska.run();
}

void userHandler(HttpRequest request, {String userId}) async {
    request.response.write('authHandler: ${request.uri.path} |> $userId');
}
```