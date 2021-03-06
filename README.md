# Laska

Laska is a server-side microframework for [Dart](https://dart.dev/).

## Current state

Active development, **not for production use**.

## Summary

- [x] Dynamic routing with placeholders and wildcards
- [x] Extensible Middleware support
- [ ] Template rendering
- [ ] Logging

## Example

```dart
import 'dart:io';

import 'package:laska/laska.dart';

void main() async {
  // Create new Laska object
  final laska = Laska();

  // Set global BasicAuth middleware 
  laska.Use(BasicAuth('laska', 'ermine', realm: 'Access to private zone'));

  laska.GET('/users/:userId', getUserById);
  laska.POST('/users/', createUser);

  // Start server
  await laska.run();
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