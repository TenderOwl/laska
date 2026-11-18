/// The middleware of the authentication.
///
/// The middleware checks who the caller is and leaves the answer in the
/// request, so a handler does not have to read the headers itself. Every
/// middleware answers with `401` when the caller cannot prove who it is, and
/// the answer never says why the token was refused, so an attacker learns
/// nothing about the secrets of the service.
library;

import '../errors.dart';
import '../middleware.dart';
import '../request.dart';
import 'api_key.dart';
import 'jwt.dart';
import 'principal.dart';
import 'rate_limit.dart';
import 'session.dart';

/// The header the token of the caller travels in.
const String authorizationHeader = 'authorization';

/// The header the API key of the caller travels in.
const String apiKeyHeader = 'x-api-key';

/// Requires a valid token in the `Authorization` header.
///
/// The [verifier] holds the keys of the service. When the request carries no
/// token and the middleware is not [required], the chain continues without a
/// principal.
Middleware jwtMiddleware(
  JwtVerifier verifier, {
  String header = authorizationHeader,
  String scheme = 'Bearer',
  bool required = true,
  Principal Function(JwtClaims claims)? principalBuilder,
}) {
  return (request, next) async {
    final token = _tokenOf(request, header, scheme);

    if (token == null) {
      if (!required) {
        return next();
      }
      throw _unauthorized(
        'The request carries no token',
        'no_token',
        scheme,
      );
    }

    final Jwt jwt;
    try {
      jwt = await verifier.verifyAsync(token);
    } on JwtException catch (error) {
      throw _unauthorized(
        'The token of the caller is not valid',
        error.code,
        scheme,
      );
    }

    request.principal = principalBuilder?.call(jwt.claims) ??
        Principal(
          id: jwt.claims.subject ?? jwt.claims.jwtId ?? '',
          issuer: jwt.claims.issuer,
          scopes: jwt.claims.scopes,
          claims: jwt.claims.claims,
        );

    return next();
  };
}

/// Requires a valid API key in the `x-api-key` header.
///
/// The [guard] holds the hashes of the keys of the clients. When the request
/// carries no key and the middleware is not [required], the chain continues
/// without a principal.
Middleware apiKeyMiddleware(
  ApiKeyGuard guard, {
  String header = apiKeyHeader,
  bool required = true,
}) {
  return (request, next) async {
    final key = guard.verify(request.header(header));

    if (key == null) {
      if (!required) {
        return next();
      }
      throw HttpException(
        401,
        'The request carries no valid API key',
        code: 'invalid_api_key',
      );
    }

    request.apiKey = key;
    request.principal ??= Principal(
      id: key.id,
      kind: PrincipalKind.apiKey,
      scopes: key.scopes,
    );

    return next();
  };
}

/// Requires the caller to hold the [scope].
///
/// The middleware answers with `403` when the caller is known, but may not do
/// what the route asks.
Middleware requireScope(String scope) {
  return (request, next) async {
    final principal = request.principal;
    if (principal == null) {
      throw HttpException(
        401,
        'The request carries no caller',
        code: 'unauthorized',
      );
    }

    if (!principal.hasScope(scope)) {
      throw HttpException(
        403,
        'The caller may not do "$scope"',
        code: 'insufficient_scope',
        headers: const <String, String>{
          'www-authenticate': 'Bearer error="insufficient_scope"',
        },
      );
    }

    return next();
  };
}

/// Puts the session of the caller in the request.
///
/// The session travels in a cookie. When the cookie names a session that is
/// unknown or that has expired, the request continues without a session, so
/// the route may decide what to do with it.
Middleware sessionMiddleware(
  SessionStore store, {
  String cookieName = sessionCookieName,
  bool required = false,
}) {
  return (request, next) async {
    final id = readCookie(request.header('cookie'), cookieName);
    if (id == null || id.isEmpty) {
      if (required) {
        throw HttpException(
          401,
          'The request carries no session',
          code: 'no_session',
        );
      }
      return next();
    }

    final session = await store.find(id);
    if (session == null || session.isExpired()) {
      if (session != null) {
        await store.delete(session.id);
      }
      if (required) {
        throw HttpException(
          401,
          'The session of the caller is not valid',
          code: 'invalid_session',
        );
      }
      return next();
    }

    request.session = session;
    final userId = session.data['user_id'];
    request.principal ??= Principal(
      id: userId is String && userId.isNotEmpty ? userId : session.id,
      kind: PrincipalKind.user,
      claims: session.data,
    );

    return next();
  };
}

/// Requires the request to carry a session.
Middleware requireSession() {
  return (request, next) async {
    if (request.session == null) {
      throw HttpException(
        401,
        'The request carries no session',
        code: 'no_session',
      );
    }
    return next();
  };
}

/// Limits how many calls a caller may make.
///
/// The caller gets a `429` and a hint of when it may come back, instead of a
/// queue that grows until the service falls over.
Middleware rateLimitMiddleware(
  RateLimiter limiter, {
  String Function(Request request)? key,
}) {
  return (request, next) async {
    final bucket = key?.call(request) ?? rateLimitKeyOf(request);
    final wait = limiter.consume(bucket);

    if (wait != null) {
      final seconds = wait.inSeconds < 1 ? 1 : wait.inSeconds;
      throw HttpException(
        429,
        'The caller made too many requests',
        code: 'rate_limited',
        headers: <String, String>{'retry-after': '$seconds'},
      );
    }

    return next();
  };
}

/// The key of the bucket of the caller of the [request].
///
/// The caller is known by the session or by the token, so the limit follows
/// the caller and not the connection. A caller nobody knows is limited by
/// its address.
String rateLimitKeyOf(Request request) {
  final principal = request.principal;
  if (principal != null && principal.id.isNotEmpty) {
    return 'principal:${principal.id}';
  }

  final apiKey = request.apiKey;
  if (apiKey != null) {
    return 'key:${apiKey.id}';
  }

  return 'address:${clientAddressOf(request)}';
}

/// The address of the caller of the [request].
String clientAddressOf(Request request) {
  final forwarded = request.header('x-forwarded-for');
  if (forwarded != null && forwarded.isNotEmpty) {
    return forwarded.split(',').first.trim();
  }

  return request.header('x-real-ip') ?? 'unknown';
}

/// The token out of the header of the request.
String? _tokenOf(Request request, String header, String scheme) {
  final value = request.header(header);
  if (value == null || value.isEmpty) {
    return null;
  }

  final separator = value.indexOf(' ');
  if (separator == -1) {
    return null;
  }

  if (value.substring(0, separator).toLowerCase() != scheme.toLowerCase()) {
    return null;
  }

  final token = value.substring(separator + 1).trim();
  return token.isEmpty ? null : token;
}

/// The error of a request that cannot be authenticated.
HttpException _unauthorized(String message, String code, String scheme) {
  return HttpException(
    401,
    message,
    code: code,
    headers: <String, String>{
      'www-authenticate': '$scheme error="$code"',
    },
  );
}
