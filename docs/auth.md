# The authentication of the callers

A service has to know who is calling before it does anything. Laska ships the
three ways a service is called in practice — a token, an API key and a session
— and the middleware that checks them.

Every middleware of this page answers with `401` when the caller cannot prove
who it is, and with `403` when the caller is known but may not do what the
route asks. The answer never says *why* the token was refused: an attacker
learns nothing about the keys of the service.

## The tokens

A token is a JWT: a header, a payload and a signature. The runtime signs and
verifies them with `HS256`, `RS256`, `RS384`, `RS512`, `ES256`, `ES384` and
`ES512`.

```dart
import 'dart:convert';

import 'package:laska_core/laska_core.dart';

final signer = JwtSigner(
  HmacJwtKey(utf8.encode(secret), kid: 'auth-1'),
);

final token = signer.sign(
  JwtClaims(
    subject: 'u_1',
    issuer: 'https://auth.example',
    audience: <String>['https://api.example'],
    expiresAt: DateTime.now().add(const Duration(minutes: 15)),
    claims: <String, Object?>{'scope': 'users:read'},
  ),
);
```

The verifier holds the keys of the service:

```dart
final verifier = JwtVerifier(keys: <JwtKey>[key]);

final jwt = await verifier.verifyAsync(token);
print(jwt.claims.subject);
```

The verifier does **not** trust the header of the token. The algorithm of the
token has to be the algorithm of the key that signed it, so a token that asks
for `none` or for another algorithm is refused with `algorithm_unsupported` or
`algorithm_mismatch`. The claims are checked too: the issuer, the audience,
the expiry (`token_expired`) and the start of the validity
(`token_not_yet_valid`).

The middleware puts the caller in the request, so a handler never reads the
headers itself:

```dart
app.use(jwtMiddleware(verifier));

app.get('/me', (ctx) {
  final principal = ctx.request.principal!;
  return ctx.json(<String, Object?>{'id': principal.id});
});
```

The middleware answers with `401` and a `www-authenticate` header that names
the reason in a machine readable way (`no_token`, `token_expired`,
`signature_invalid`, …).

## The keys of the service

A service that verifies the tokens of its callers has to publish the keys it
verifies with, so the callers may fetch them. That is the JWKS — a JSON Web Key
Set.

```console
$ dart run laska_cli:laska keys generate --alg es256 --out keys --kid auth-2026
generated: keys/auth-2026.private.json
generated: keys/jwks.json
```

The command writes the private key in a file of its own and the key set of the
service next to it. The private file holds a secret and must not be published;
the key set holds the public parts only.

The runtime reads the key set and refreshes it when it needs to:

```dart
final cache = JwksCache(
  uri: Uri.parse('https://auth.example/.well-known/jwks.json'),
);

final verifier = JwtVerifier.withSource(cache);
```

The cache holds the key set for fifteen minutes. When a token arrives with a
`kid` the cache does not know, it refreshes the set once — and never more than
once every ten seconds, so a caller that sends made-up `kid`s cannot turn the
service into a client of itself.

The rotation of the keys is a matter of publishing a new key with a new `kid`
and of signing with it. The old key stays in the set until the tokens it
signed expire.

## The API keys

A service that is called by another service — or by a machine — often answers
with an API key instead of a token. The key is a secret the client sends in
the `x-api-key` header, and the service only keeps its hash, so a leak of the
database of the service does not leak the keys of the clients.

```dart
final guard = ApiKeyGuard(<ApiKey>[
  ApiKey(id: 'ci', hash: hashApiKey(secret), scopes: <String>['jobs:write']),
]);

app.use(apiKeyMiddleware(guard));
```

The keys are compared without telling how much of them is equal, so the answer
of the service does not tell an attacker how much of a key he guessed.

## The sessions

A session is a small piece of state that lives on the server: the user is
logged in and the session holds what the service remembers about them. The
session is identified by a random id that travels in a cookie.

```dart
final store = MemorySessionStore();

app.use(sessionMiddleware(store));

app.post('/login', (ctx) async {
  final session = await startSession(store, data: <String, Object?>{
    'user_id': 'u_1',
  });

  final response = ctx.text('ok');
  response.headers['set-cookie'] = renderSessionCookie(session.id);
  return response;
});
```

The id of a session is **regenerated when the privileges of the session
change**, e.g. when the caller logs in:

```dart
final session = await regenerateSession(store, session);
```

The old id is dead afterwards, so an id that leaked before the login does not
give the attacker the session. That is the defence against the fixation of a
session.

The cookie is written with `HttpOnly`, with `Secure` and with `SameSite=Lax`
by default; `renderSessionCookie` takes the flags it needs. The cookie that
ends the session is rendered by `renderClearedSessionCookie`.

A service that runs in more than one process needs a store that is shared
between the processes — Redis or Postgres. `SessionStore` is the interface
for it, and `MemorySessionStore` is the store of a service that runs in one
process and the store of the tests.

## The limits

A caller that asks for too much gets a `429` and a hint of when it may come
back, instead of a queue that grows until the service falls over.

```dart
final limiter = RateLimiter(limit: 100, window: const Duration(minutes: 1));

app.use(rateLimitMiddleware(limiter));
```

The limiter is a token bucket per key. The key of the bucket is the caller
when it is known — the principal or the API key — and its address otherwise,
so the limit follows the caller and not the connection. The address is read
from `x-forwarded-for` and from `x-real-ip`.

## The scopes

A scope says what a caller may do. The middleware answers with `403` when the
caller is known but does not hold the scope of the route:

```dart
app.post(
  '/users',
  (ctx) => ctx.text('created'),
  middleware: <Object>[requireScope('users:write')],
);
```

The scope of a token is read from the claim `scope` or from the claim `scp`,
and the scope of an API key is the list of its `scopes`.

## The summary

| What the caller sends | The middleware | What the handler reads |
|---|---|---|
| `Authorization: Bearer <token>` | `jwtMiddleware(verifier)` | `ctx.request.principal` |
| `x-api-key: <key>` | `apiKeyMiddleware(guard)` | `ctx.request.apiKey`, `ctx.request.principal` |
| `Cookie: laska_session=<id>` | `sessionMiddleware(store)` | `ctx.request.session`, `ctx.request.principal` |
| — | `rateLimitMiddleware(limiter)` | — |
