# Laska

Laska is a server-side microframework for [Dart](https://dart.dev/), which aims to be a fast, simple and lightweight.

- **Routing**: Requests to function-call mapping with support for clean and dynamic URLs.
- **Middlewares**: Middlwares allow developers to modify request before it's being processed.
- **Isolates**: Laska uses Isolates to secure request processing.

### Example: "Hello world" in a Laska

```dart
import 'package:laska/laska.dart';

void main() async {
  final laska = Laska();

  laska.GET('/hello/:name',
      (context) async => await context.Text("Hello ${context.param('name')}!"));

  await run(laska);
}
```

Run this script via `dart run hello_world.dart`, then point your browser to http://localhost:3789/hello/world. That’s it.


## Current state

Active development, **not for production use**.


## Full Example

```dart
import 'dart:io';

import 'package:laska/laska.dart';

void main() async {
  // Create new Laska object
  final laska = Laska();

  // Set global BasicAuth middleware 
  laska.use(BasicAuth('laska', 'ermine', realm: 'Access to private zone'));

  laska.get('/users/:userId', getUserById);
  laska.post('/users/', createUser);

  // Start server
  await run(laska);
}

void getUserById(Context context) async {
  await context.html('User: <b>${context.params['userId']}</b>');
}

void createUser(Context context) async {
  await context.json({'status': 'created'}, statusCode: HttpStatus.created);
}
```

## Routing

Laska uses a powerful routing engine to find the right callback for each request. it's based on [Trie](https://en.wikipedia.org/wiki/Trie) data structure which let it be very performant.


## License

[MIT](https://github.com/amka/laska/blob/master/LICENSE)