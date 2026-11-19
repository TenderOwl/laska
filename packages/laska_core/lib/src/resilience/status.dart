/// The mapping between the errors of the framework, the HTTP statuses and the
/// statuses of the gRPC protocol.
///
/// The mapping lives in one place, so a service answers the same problem the
/// same way whatever transport the caller used.
library;

import '../errors.dart';
import 'errors.dart';

/// The status codes of the gRPC protocol.
class GrpcStatus {
  const GrpcStatus._();

  /// The call succeeded.
  static const int ok = 0;

  /// The caller cancelled the call.
  static const int cancelled = 1;

  /// The call was unknown to the server.
  static const int unknown = 2;

  /// The arguments of the call were wrong.
  static const int invalidArgument = 3;

  /// The call died before it finished.
  static const int deadlineExceeded = 4;

  /// The resource does not exist.
  static const int notFound = 5;

  /// The resource already exists.
  static const int alreadyExists = 6;

  /// The caller is not allowed to make the call.
  static const int permissionDenied = 7;

  /// The service has no room left for the call.
  static const int resourceExhausted = 8;

  /// The request was wrong.
  static const int failedPrecondition = 9;

  /// The call was aborted.
  static const int aborted = 10;

  /// The call was made in the wrong range.
  static const int outOfRange = 11;

  /// The method is not implemented.
  static const int unimplemented = 12;

  /// The server hit an internal error.
  static const int internal = 13;

  /// The service is not reachable.
  static const int unavailable = 14;

  /// The data was lost.
  static const int dataLoss = 15;

  /// The call was not authenticated.
  static const int unauthenticated = 16;
}

/// Maps an HTTP status to the status of the gRPC protocol.
int grpcStatusOf(int httpStatus) {
  switch (httpStatus) {
    case 200:
    case 201:
    case 204:
      return GrpcStatus.ok;
    case 400:
      return GrpcStatus.invalidArgument;
    case 401:
      return GrpcStatus.unauthenticated;
    case 403:
      return GrpcStatus.permissionDenied;
    case 404:
      return GrpcStatus.notFound;
    case 409:
      return GrpcStatus.alreadyExists;
    case 412:
      return GrpcStatus.failedPrecondition;
    case 416:
      return GrpcStatus.outOfRange;
    case 429:
      return GrpcStatus.resourceExhausted;
    case 499:
      return GrpcStatus.cancelled;
    case 501:
      return GrpcStatus.unimplemented;
    case 503:
      return GrpcStatus.unavailable;
    case 504:
      return GrpcStatus.deadlineExceeded;
    default:
      if (httpStatus >= 500) {
        return GrpcStatus.internal;
      }
      if (httpStatus >= 400) {
        return GrpcStatus.unknown;
      }
      return GrpcStatus.ok;
  }
}

/// Maps the status of the gRPC protocol to an HTTP status.
int httpStatusOfGrpc(int grpcStatus) {
  switch (grpcStatus) {
    case GrpcStatus.ok:
      return 200;
    case GrpcStatus.cancelled:
      return 499;
    case GrpcStatus.invalidArgument:
      return 400;
    case GrpcStatus.deadlineExceeded:
      return 504;
    case GrpcStatus.notFound:
      return 404;
    case GrpcStatus.alreadyExists:
      return 409;
    case GrpcStatus.permissionDenied:
      return 403;
    case GrpcStatus.resourceExhausted:
      return 429;
    case GrpcStatus.failedPrecondition:
      return 400;
    case GrpcStatus.aborted:
      return 409;
    case GrpcStatus.outOfRange:
      return 400;
    case GrpcStatus.unimplemented:
      return 501;
    case GrpcStatus.unavailable:
      return 503;
    case GrpcStatus.dataLoss:
      return 500;
    case GrpcStatus.unauthenticated:
      return 401;
    case GrpcStatus.internal:
    default:
      return 500;
  }
}

/// Maps an error of the framework to the status of the gRPC protocol.
///
/// The mapping goes through the HTTP status, so a service answers the same
/// problem the same way whatever transport the caller used.
int grpcStatusOfError(Object error) {
  if (error is FormatException) {
    // A payload the framework cannot read is a wrong argument of the caller,
    // the same way it is over HTTP.
    return GrpcStatus.invalidArgument;
  }
  return grpcStatusOf(httpStatusOfError(error));
}

/// Maps an error of the framework to the HTTP status it is answered with.
///
/// The mapping is what makes a graceful degradation possible: a call to a
/// dependency whose circuit is open is answered with `503`, so the caller can
/// fall back instead of waiting for a timeout.
int httpStatusOfError(Object error) {
  if (error is HttpException) {
    return error.status;
  }
  if (error is DependencyTimeoutException) {
    return 504;
  }
  if (error is CircuitOpenException) {
    return 503;
  }
  if (error is BulkheadFullException) {
    return 503;
  }
  if (error is DependencyFailure) {
    final status = error.statusCode;
    if (status != null && status >= 400) {
      return status;
    }
    return 502;
  }
  return 500;
}

/// The machine readable code of an error of the framework.
String? errorCodeOf(Object error) {
  if (error is HttpException) {
    return error.code;
  }
  if (error is DependencyTimeoutException) {
    return 'dependency_timeout';
  }
  if (error is CircuitOpenException) {
    return 'circuit_open';
  }
  if (error is BulkheadFullException) {
    return 'dependency_overloaded';
  }
  if (error is DependencyFailure) {
    return 'dependency_failure';
  }
  return null;
}

/// Whether an error of the framework is worth another attempt.
///
/// The errors that are not worth a retry are the ones that repeat: an open
/// circuit and a full bulkhead fail fast.
bool isRetryableError(Object error) {
  if (error is DependencyTimeoutException) {
    return true;
  }
  if (error is DependencyFailure) {
    return true;
  }
  return false;
}
