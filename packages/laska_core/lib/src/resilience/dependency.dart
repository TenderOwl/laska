/// The call to a dependency, with the policies of the contract applied.
///
/// The dependency is the one place where a timeout, a retry, a circuit
/// breaker and a bulkhead meet, so every outgoing call of a service behaves
/// the same way.
library;

import 'dart:async';
import 'dart:math';

import '../telemetry/tracer.dart';
import '../transport.dart';
import 'bulkhead.dart';
import 'circuit_breaker.dart';
import 'errors.dart';
import 'policy.dart';
import 'status.dart';

/// A dependency of the service.
class Dependency {
  /// Creates a dependency named [name], reached through [transport].
  Dependency({
    required this.name,
    required this.transport,
    this.policy = const DependencyPolicy(),
    this.defaultTimeout = const Duration(seconds: 2),
    this.tracer,
    Random? random,
  }) : _random = random ?? Random();

  /// Name of the dependency, e.g. `users`.
  final String name;

  /// The transport the dependency is reached through.
  final ServiceTransport transport;

  /// The policy of the calls to the dependency.
  final DependencyPolicy policy;

  /// How long an attempt may take when the policy has no timeout of its own.
  ///
  /// A call without a timeout is a bug, so the dependency always has one.
  final Duration defaultTimeout;

  /// The tracer of the calls, when the calls are traced.
  final Tracer? tracer;

  final Random _random;
  CircuitBreaker? _breaker;
  Bulkhead? _bulkhead;

  /// The circuit breaker of the dependency, when the policy has one.
  CircuitBreaker? get circuitBreaker {
    final breakerPolicy = policy.circuitBreaker;
    if (breakerPolicy == null) {
      return null;
    }
    return _breaker ??= CircuitBreaker(name, breakerPolicy);
  }

  /// The bulkhead of the dependency, when the policy has one.
  Bulkhead? get bulkhead {
    final bulkheadPolicy = policy.bulkhead;
    if (bulkheadPolicy == null) {
      return null;
    }
    return _bulkhead ??= Bulkhead(name, bulkheadPolicy);
  }

  /// Calls the dependency.
  ///
  /// The [policy] overrides the timeout, the retry and the idempotency of the
  /// calls, so a method of a contract can be called with the policy the
  /// contract declares. The circuit breaker and the bulkhead belong to the
  /// dependency and are shared by every call.
  ///
  /// The call is traced when a tracer is given: one client span holds the
  /// number of the attempts and the status of the answer.
  Future<TransportResponse> call(
    TransportRequest request, {
    DependencyPolicy? policy,
    String? operation,
    Map<String, Object?> attributes = const <String, Object?>{},
  }) async {
    final effective = policy ?? this.policy;
    final tracer = this.tracer;
    final span = tracer?.startSpan(
      operation ?? name,
      kind: SpanKind.client,
      attributes: <String, Object?>{
        'rpc.service': name,
        if (operation != null) 'rpc.method': operation,
        ...attributes,
      },
    );

    if (tracer != null && span != null) {
      tracer.inject(span.context, request.headers);
    }

    try {
      final result =
          await runWithSpan(span, () => _attempt(request, effective));
      span?.setAttribute(
          'http.response.status_code', result.response.statusCode);
      span?.setAttribute('rpc.attempts', result.attempts);
      return result.response;
    } catch (error, stackTrace) {
      span?.recordError(error, stackTrace);
      rethrow;
    } finally {
      span?.end();
    }
  }

  /// Makes the attempts of the call, until one of them works.
  Future<_Attempt> _attempt(
    TransportRequest request,
    DependencyPolicy policy,
  ) async {
    final attempts = policy.idempotent ? policy.retry.maxAttempts : 1;
    var attempt = 0;

    while (true) {
      attempt++;
      try {
        final response = await _send(request, policy);
        return _Attempt(response, attempt);
      } catch (error) {
        if (attempt >= attempts) {
          rethrow;
        }
        if (!isRetryableError(error)) {
          rethrow;
        }
        final failure = error is DependencyFailure ? error : null;
        if (failure != null &&
            !policy.retry.shouldRetryStatus(failure.statusCode)) {
          rethrow;
        }
        await Future<void>.delayed(
          policy.retry.backoffFor(
            attempt,
            retryAfter: failure?.retryAfter,
            random: _random,
          ),
        );
      }
    }
  }

  /// Makes one attempt of the call.
  Future<TransportResponse> _send(
    TransportRequest request,
    DependencyPolicy policy,
  ) async {
    final breaker = circuitBreaker;
    if (breaker == null) {
      return _sendOnce(request, policy);
    }
    return breaker.call(() => _sendOnce(request, policy));
  }

  /// Sends the request to the dependency and checks the answer.
  Future<TransportResponse> _sendOnce(
    TransportRequest request,
    DependencyPolicy policy,
  ) async {
    final timeout = policy.timeout ?? defaultTimeout;
    try {
      final response = await transport.send(request).timeout(timeout);
      if (response.statusCode >= 400) {
        throw DependencyFailure(
          name,
          statusCode: response.statusCode,
          message: 'The dependency answered with ${response.statusCode}',
          body: response.text,
          headers: response.headers,
          retryAfter: parseRetryAfter(response.headers),
        );
      }
      return response;
    } on TimeoutException {
      throw DependencyTimeoutException(name, timeout);
    } on DependencyFailure catch (error) {
      throw error.dependency.isEmpty ? error.withDependency(name) : error;
    } catch (error) {
      throw DependencyFailure(name, message: error.toString(), cause: error);
    }
  }
}

/// The answer of a call and the number of the attempts it took.
class _Attempt {
  _Attempt(this.response, this.attempts);

  /// The answer of the dependency.
  final TransportResponse response;

  /// How many attempts the call took.
  final int attempts;
}
