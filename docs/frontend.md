# The frontend of a workspace

A workspace does not hold only APIs. Sometimes one of its services carries the
frontend of the workspace — a landing page, an admin panel — and the frontend
calls the other services over their contracts.

That service is the **app** of the workspace: the third kind of participant,
next to the `service` and the `gateway`.

| Participant | What it is |
|---|---|
| `service` | A service of a contract. It answers over the REST projection of the contract and over gRPC. |
| `gateway` | A service that calls another service of the workspace and answers with a view of its records. |
| `app` | The service that carries the frontend. It serves the files of the frontend and calls the services behind it. |

The framework does not build the frontend and it does not render the
templates: the application writes the HTML and the toolchain of the
application builds the frontend. The runtime serves the files and forwards the
calls.

## Scaffold an app

```console
$ laska new app admin
created: admin/lib/app.dart
created: admin/bin/server.dart
created: admin/web/index.html
created: admin/web/app.js
created: admin/test/app_test.dart
created: admin/pubspec.yaml
created: laska.yaml

Run it with: laska dev
```

The command writes an app that is ready to run and adds it to the manifest of
the workspace:

```yaml
services:
  - name: users
    entrypoint: users/bin/server.dart
    port: 8080
  - name: admin
    kind: app
    entrypoint: admin/bin/server.dart
    port: 8081
    depends_on: [users]
```

The `kind` of the app is written in the manifest, so the tools of the
workspace and the reader of the manifest know what the participant is. A
service without a kind is a service of a contract, and the manifest of a
workspace of services stays the manifest it was.

The port of the app is the first port no service of the workspace listens to,
so the workspace starts without a clash. The option `--port` wins over it.

The app calls every service of the workspace by default. The option `--calls`
narrows that down, and it may be repeated:

```console
$ laska new app admin --calls users --calls billing
```

## The frontend of the app

The app serves the files of the directory `web/`:

```dart
app.staticFiles('/', files, fallback: 'index.html');
```

The build of the frontend belongs to the application: run `npm run build` (or
the bundler of your choice) in the directory of the frontend and put the
result of it in `web/`. The runtime serves the files and nothing else — it
does not bundle, it does not watch the files and it does not know what a
JavaScript module is.

The `fallback` is the file that answers for a path that names no file, so the
router of the frontend takes it from there. The paths of the API of the
services are more specific than the files, so they reach the services and not
the frontend.

## The calls of the frontend

The app calls the services behind it through the **generated client** of their
contract, so the calls are typed and they carry the policy of the contract:

```dart
final users = UsersServiceClient(
  baseUrl: Platform.environment['USERS_URL'] ?? 'http://127.0.0.1:8080',
);

registerUsersService(app, UsersProxy(users), grpc: false);
```

The proxy implements the service of the contract and forwards the call to the
service behind the app:

```dart
class UsersProxy implements UsersService {
  UsersProxy(this._client);

  final UsersServiceClient _client;

  @override
  Future<User> getUser(GetUserRequest request) =>
      _client.getUser(request, headers: _headersOfTheCaller());
}
```

The headers of the caller travel with the call, so the token of the session of
the browser reaches the service behind the app and the middleware of the
authentication checks it there:

```dart
Map<String, String> _headersOfTheCaller() {
  final request = Zone.current[_caller];
  if (request is! Request) {
    return const <String, String>{};
  }
  final token = request.header('authorization');
  if (token == null) {
    return const <String, String>{};
  }
  return <String, String>{'authorization': token};
}
```

The request of the caller is kept in the zone of the call by a middleware, so
the proxy reaches it without the signature of the service of the contract
holding it:

```dart
Middleware _keepTheCaller() => (request, next) {
      return runZoned(
        () => next(),
        zoneValues: <Object, Object?>{_caller: request},
      );
    };
```

The app registers the projection of the contract, so the paths of the API of
the service are the paths of the frontend: the browser calls `/v1/users/u_1`
on the app, and the app calls the service behind it.

## The image of the app

The image of an app holds the files of the frontend, because the app serves
them:

```dockerfile
FROM scratch
COPY --from=build /runtime/ /
COPY --from=build /app/server /app/server

# The app serves the files of the frontend, so they are part of the image.
COPY --from=build /app/web /app/web
ENV LASKA_WEB_ROOT=/app/web
```

The variable `LASKA_WEB_ROOT` points at the files inside the image, and the app
reads it:

```dart
final files = Platform.environment['LASKA_WEB_ROOT'] ?? 'web';
```

The image of a service of a contract holds no files of a frontend — it holds
the binary alone.

## What the runtime does not do

- **It does not bundle the frontend.** The bundler of the application builds
  it, and the runtime serves the result.
- **It does not render the templates.** The HTML of an answer is written by
  the application. A service that needs templates picks a library for them.
- **It does not hold the state of the browser.** The state of the caller lives
  in the services of the workspace, and the frontend holds the token of it.

See [the guide of the files](static-files.md) for the files of a service and
[the guide of the contracts](contracts.md) for the headers of a call.

The example of the repository holds an app like this one:
[`example/workspace/apps/admin`](../example/workspace).
