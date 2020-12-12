# Laska

Laska is a server-side microframework for [Dart](https://dart.dev/).

Currently, in development, **not for production use**.

## Summary

- [x] Dynamic routing with placeholders and wildcards
- [x] Concurrency via [Isolates](https://api.dart.dev/stable/2.10.4/dart-isolate/Isolate-class.html)
- [ ] Extensible Middleware support
- [ ] Template rendering
- [ ] Logging

## Example

```dart
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
```

## License

[MIT](https://github.com/amka/laska/blob/master/LICENSE)