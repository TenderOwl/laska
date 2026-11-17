/// Errors that map directly to an HTTP response.
library;

/// An error with an associated HTTP status code.
///
/// The runtime renders it as an RFC 9457 `application/problem+json` document.
class HttpException implements Exception {
  /// Creates an exception for [status] with a human readable [message].
  HttpException(
    this.status,
    this.message, {
    this.code,
    this.details,
    this.headers,
  });

  /// HTTP status code, e.g. `404`.
  final int status;

  /// Human readable description of what went wrong.
  final String message;

  /// Machine readable error code, e.g. `user_not_found`.
  final String? code;

  /// Optional structured details, e.g. per-field validation errors.
  final Object? details;

  /// Extra headers to send along with the error response.
  final Map<String, String>? headers;

  @override
  String toString() => 'HttpException($status): $message';
}

/// Raised by generated clients when the server answered with an error status.
class LaskaApiException implements Exception {
  /// Creates an exception for a response with [statusCode] and [body].
  LaskaApiException(this.statusCode, this.body);

  /// HTTP status code returned by the server.
  final int statusCode;

  /// Raw response body.
  final String body;

  @override
  String toString() => 'LaskaApiException($statusCode): $body';
}
