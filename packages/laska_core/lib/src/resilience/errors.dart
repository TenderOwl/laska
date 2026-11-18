/// The errors of a call to another service.
///
/// The errors are the same on every transport, so a service can handle the
/// failure of a dependency the same way whether it speaks HTTP or gRPC.
library;

/// A call to a dependency failed.
///
/// The error covers both a network failure and an error answer of the
/// dependency. The [statusCode] is `null` when the call never reached the
/// dependency.
class DependencyFailure implements Exception {
  /// Creates a failure of the dependency [dependency].
  DependencyFailure(
    this.dependency, {
    this.statusCode,
    required this.message,
    this.body = '',
    this.headers = const <String, String>{},
    this.retryAfter,
    this.cause,
  });

  /// Name of the dependency that failed.
  final String dependency;

  /// The status the dependency answered with, `null` when it never answered.
  final int? statusCode;

  /// Human readable description of the failure.
  final String message;

  /// The body of the answer of the dependency.
  final String body;

  /// The headers of the answer of the dependency.
  final Map<String, String> headers;

  /// How long the dependency asked the caller to wait.
  final Duration? retryAfter;

  /// The original error, when there was one.
  final Object? cause;

  /// A copy of this failure that belongs to the dependency [dependency].
  DependencyFailure withDependency(String dependency) => DependencyFailure(
        dependency,
        statusCode: statusCode,
        message: message,
        body: body,
        headers: headers,
        retryAfter: retryAfter,
        cause: cause,
      );

  @override
  String toString() => 'DependencyFailure($dependency'
      '${statusCode == null ? '' : ', $statusCode'}: $message)';
}

/// An attempt of a call to a dependency took too long.
class DependencyTimeoutException implements Exception {
  /// Creates a timeout of the dependency [dependency].
  DependencyTimeoutException(this.dependency, this.timeout);

  /// Name of the dependency that timed out.
  final String dependency;

  /// How long the attempt was allowed to take.
  final Duration timeout;

  @override
  String toString() =>
      'DependencyTimeoutException($dependency): ${timeout.inMilliseconds}ms';
}

/// The circuit of a dependency is open, so the call was not made.
class CircuitOpenException implements Exception {
  /// Creates an open circuit of the dependency [dependency].
  CircuitOpenException(this.dependency, this.retryAfter);

  /// Name of the dependency whose circuit is open.
  final String dependency;

  /// How long the caller should wait before trying again.
  final Duration retryAfter;

  @override
  String toString() =>
      'CircuitOpenException($dependency): open for ${retryAfter.inMilliseconds}ms';
}

/// The bulkhead of a dependency is full, so the call was not made.
class BulkheadFullException implements Exception {
  /// Creates a full bulkhead of the dependency [dependency].
  BulkheadFullException(this.dependency);

  /// Name of the dependency whose bulkhead is full.
  final String dependency;

  @override
  String toString() => 'BulkheadFullException($dependency): no free slot';
}

/// A service is not known to the discovery.
class ServiceNotFoundException implements Exception {
  /// Creates an exception for the unknown service [name].
  ServiceNotFoundException(this.name, {this.known = const <String>[]});

  /// Name of the service that is not known.
  final String name;

  /// The names of the services that are known.
  final List<String> known;

  @override
  String toString() => 'ServiceNotFoundException($name)';
}
