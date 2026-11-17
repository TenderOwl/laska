import 'dart:math';

import '../logger.dart';
import '../middleware.dart';
import '../response.dart';

/// Assigns a request id to every request.
///
/// The id is taken from the `x-request-id` header when the client sends one,
/// so a request can be correlated across services. Otherwise a random id is
/// generated.
Middleware requestIdMiddleware({String header = 'x-request-id'}) {
  final random = Random();
  return (request, next) async {
    request.id ??= request.header(header) ??
        '${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}-'
            '${random.nextInt(1 << 32).toRadixString(36)}';
    final response = await next();
    if (request.id != null) {
      response.headers.putIfAbsent(header, () => request.id!);
    }
    return response;
  };
}

/// Logs one record per request.
///
/// The record holds the method, the path, the status, the duration and the
/// request id, so a request can be followed from the log into a trace.
Middleware loggingMiddleware(Logger logger) {
  return (request, next) async {
    final stopwatch = Stopwatch()..start();
    try {
      final response = await next();
      logger.info(
        'request',
        <String, Object?>{
          'method': request.method,
          'path': request.path,
          'status': response.status,
          'duration_ms': stopwatch.elapsedMicroseconds / 1000,
          if (request.id != null) 'request_id': request.id,
        },
      );
      return response;
    } catch (error) {
      logger.error(
        'request failed',
        <String, Object?>{
          'method': request.method,
          'path': request.path,
          'duration_ms': stopwatch.elapsedMicroseconds / 1000,
          if (request.id != null) 'request_id': request.id,
          'error': error.toString(),
        },
      );
      rethrow;
    }
  };
}

/// The CORS configuration of [corsMiddleware].
class CorsOptions {
  /// Creates CORS options.
  const CorsOptions({
    this.allowedOrigins = const <String>['*'],
    this.allowedMethods = const <String>[
      'GET',
      'POST',
      'PUT',
      'PATCH',
      'DELETE',
      'OPTIONS',
    ],
    this.allowedHeaders = const <String>['content-type', 'authorization'],
    this.exposedHeaders = const <String>[],
    this.credentials = false,
    this.maxAge = const Duration(hours: 24),
  });

  /// The origins that may call the service, `*` for every origin.
  final List<String> allowedOrigins;

  /// The methods a cross origin request may use.
  final List<String> allowedMethods;

  /// The headers a cross origin request may send.
  final List<String> allowedHeaders;

  /// The headers the browser may read from the response.
  final List<String> exposedHeaders;

  /// Whether cookies and credentials are allowed.
  final bool credentials;

  /// How long a preflight response may be cached.
  final Duration maxAge;
}

/// Answers preflight requests and adds the CORS headers.
Middleware corsMiddleware([CorsOptions options = const CorsOptions()]) {
  return (request, next) async {
    final origin = request.header('origin');
    if (origin == null) {
      return next();
    }

    final allowed = options.allowedOrigins.contains('*') ||
        options.allowedOrigins.contains(origin);

    if (request.method == 'OPTIONS' &&
        request.header('access-control-request-method') != null) {
      final response = Response(status: 204);
      _applyCorsHeaders(response, origin, allowed, options);
      return response;
    }

    final response = await next();
    _applyCorsHeaders(response, origin, allowed, options);
    return response;
  };
}

void _applyCorsHeaders(
  Response response,
  String origin,
  bool allowed,
  CorsOptions options,
) {
  if (!allowed) {
    return;
  }
  response.headers['access-control-allow-origin'] =
      options.allowedOrigins.contains('*') ? '*' : origin;
  if (options.credentials) {
    response.headers['access-control-allow-credentials'] = 'true';
  }
  if (options.exposedHeaders.isNotEmpty) {
    response.headers['access-control-expose-headers'] =
        options.exposedHeaders.join(', ');
  }
}

/// Adds the security headers every service should send.
Middleware securityHeadersMiddleware({
  Map<String, String> headers = const <String, String>{
    'x-content-type-options': 'nosniff',
    'x-frame-options': 'DENY',
    'referrer-policy': 'no-referrer',
  },
}) {
  return (request, next) async {
    final response = await next();
    response.headers.addAll(headers);
    return response;
  };
}
