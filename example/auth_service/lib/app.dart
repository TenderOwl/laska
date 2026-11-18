import 'package:laska_core/laska_core.dart';

import 'keys.dart';

/// Builds the application of the example.
///
/// The example shows the ways a caller may prove who it is: a token, a scope
/// of the token, the API key of a machine and the session of a browser. Every
/// route says what it needs, and the middleware of the route answers with a
/// `401` or a `403` when the caller does not have it — never with the reason,
/// so an attacker learns nothing about the secrets of the service.
Future<Laska> buildApp({
  required ServiceKeys keys,
  RateLimiter? limiter,
}) async {
  final app = Laska();

  // The observability is installed before the routes, so its middleware runs
  // before the middleware of the routes.
  await Observability.install(app);

  // The limit of the callers is global: it runs before the routes, so a
  // caller that floods the service never reaches a handler.
  if (limiter != null) {
    app.use(rateLimitMiddleware(limiter));
  }

  // The middleware of the routes is registered under a name, so a route says
  // what it needs and the whole chain of the service stays in one place.
  app.alias('token', jwtMiddleware(keys.verifier));
  app.alias('admin', requireScope('admin'));
  app.alias('key', apiKeyMiddleware(keys.apiKeys));
  app.alias('session', sessionMiddleware(keys.sessions, required: true));

  app.get('/public', (ctx) {
    return ctx.json(<String, Object?>{
      'message': 'This route is open to everyone.',
    });
  });

  app.post('/login', (ctx) {
    final body = ctx.request.json();

    if (body['name'] != 'ada' || body['password'] != 'lovelace') {
      throw HttpException(
        401,
        'The name or the password is wrong.',
        code: 'invalid_credentials',
      );
    }

    final scopes = body['admin'] == true
        ? const <String>['read', 'admin']
        : const <String>['read'];

    final token = keys.signer.sign(
      JwtClaims(
        issuer: serviceIssuer,
        audience: const <String>[serviceAudience],
        subject: 'ada',
        expiresAt: DateTime.now().add(const Duration(hours: 1)),
        claims: <String, Object?>{'scope': scopes.join(' ')},
      ),
    );

    return ctx.json(<String, Object?>{
      'token': token,
      'type': 'Bearer',
      'expires_in': 3600,
    });
  });

  app.post('/session', (ctx) async {
    final body = ctx.request.json();

    if (body['name'] != 'ada' || body['password'] != 'lovelace') {
      throw HttpException(
        401,
        'The name or the password is wrong.',
        code: 'invalid_credentials',
      );
    }

    // The session gets a fresh id, so an id the caller knew before the login
    // cannot be used after it.
    final session = await startSession(
      keys.sessions,
      data: <String, Object?>{'user_id': 'ada'},
    );

    return Response.json(
      <String, Object?>{'user_id': session.data['user_id']},
      status: 201,
      headers: <String, String>{
        'set-cookie':
            '$sessionCookieName=${session.id}; Path=/; HttpOnly; SameSite=Lax',
      },
    );
  });

  app.get('/me', (ctx) {
    final principal = ctx.request.principal!;
    return ctx.json(<String, Object?>{
      'id': principal.id,
      'scopes': principal.scopes,
    });
  }, middleware: <Object>['token']);

  app.get('/admin', (ctx) {
    return ctx.json(<String, Object?>{
      'message': 'Only an administrator sees this.',
    });
  }, middleware: <Object>['token', 'admin']);

  app.get('/machine', (ctx) {
    final key = ctx.request.apiKey!;
    return ctx.json(<String, Object?>{'client': key.id, 'scopes': key.scopes});
  }, middleware: <Object>['key']);

  app.get('/session', (ctx) {
    final session = ctx.request.session!;
    return ctx.json(<String, Object?>{'user_id': session.data['user_id']});
  }, middleware: <Object>['session']);

  return app;
}
