# The authentication of the callers

A service that shows the four ways a caller may prove who it is, and what the
runtime answers when the proof is missing.

| Route | What it needs | What it answers |
|---|---|---|
| `GET /public` | nothing | `200` |
| `POST /login` | the name and the password | a token |
| `POST /session` | the name and the password | a session and a cookie |
| `GET /me` | a token | the caller and its scopes |
| `GET /admin` | a token with the scope `admin` | `403` without the scope |
| `GET /machine` | the API key of the machine | `401` without the key |
| `GET /session` | the session of the browser | `401` without the session |

## Run it

```console
$ cd example/auth_service
$ dart run lib/main.dart
```

```console
$ curl -s localhost:8080/login -H 'content-type: application/json' \
    -d '{"name":"ada","password":"lovelace"}'
```

## The parts

The keys of the service live in `lib/keys.dart`: the signer that signs the
tokens, the verifier that checks them, the guard of the API keys and the store
of the sessions. The routes live in `lib/app.dart`.

The middleware of the routes is registered under a name, so a route says what
it needs and the chain of the service stays in one place:

```dart
app.alias('token', jwtMiddleware(keys.verifier));
app.alias('admin', requireScope('admin'));

app.get('/admin', (ctx) {
  return ctx.json(<String, Object?>{'message': 'Only an administrator sees this.'});
}, middleware: <Object>['token', 'admin']);
```

The middleware leaves the answer in the request, so the handler asks the
request who the caller is instead of reading the headers itself:

```dart
app.get('/me', (ctx) {
  final principal = ctx.request.principal!;
  return ctx.json(<String, Object?>{'id': principal.id, 'scopes': principal.scopes});
}, middleware: <Object>['token']);
```

The refusal never says what is wrong with the secret of the caller: the answer
is a `401` or a `403` with a code, and the details stay inside the service.

## The test

`test/auth_test.dart` runs the service in process and checks every way a
caller may be refused: no token, a token of another service, an expired token,
a token signed with another key, a missing scope, a wrong API key, a missing
session and a caller that makes too many requests.
