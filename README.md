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

void getUserById(Context context) async {
  await context.HTML('User: <b>${context.params['userId']}</b>');
}

void createUser(Context context) async {
  await context.JSON({'status': 'created'}, statusCode: HttpStatus.created);
}
```

## License

[MIT](https://github.com/amka/laska/blob/master/LICENSE)