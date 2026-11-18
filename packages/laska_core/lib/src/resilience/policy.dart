/// The policies that govern a call to another service.
///
/// The policies are values: a service describes how it wants to be called, and
/// the runtime applies the same set of rules to every dependency. The defaults
/// are deliberately strict — a call without a timeout is a bug — and every
/// policy can be overridden per method in the contract.
library;

import 'dart:math';

/// How a failed call is retried.
class RetryPolicy {
  /// Creates a retry policy.
  const RetryPolicy({
    this.maxAttempts = 3,
    this.initialBackoff = const Duration(milliseconds: 100),
    this.maxBackoff = const Duration(seconds: 2),
    this.jitter = true,
    this.retryOnStatus = const <int>{408, 425, 429, 500, 502, 503, 504},
  });

  /// A policy that never retries.
  static const RetryPolicy none = RetryPolicy(maxAttempts: 1);

  /// How many times the call is made in total, the first attempt included.
  final int maxAttempts;

  /// The backoff before the second attempt.
  final Duration initialBackoff;

  /// The longest wait between two attempts.
  final Duration maxBackoff;

  /// Whether the wait is randomised.
  ///
  /// The jitter spreads the retries of the clients of a service, so they do not
  /// hit a recovering dependency at the same moment.
  final bool jitter;

  /// The statuses that are worth another attempt.
  final Set<int> retryOnStatus;

  /// Whether a status is worth another attempt.
  bool shouldRetryStatus(int? statusCode) =>
      statusCode == null || retryOnStatus.contains(statusCode);

  /// The wait before the attempt that follows the failed [attempt].
  ///
  /// The wait grows exponentially and is capped by [maxBackoff]. When
  /// [retryAfter] is given, it wins: the dependency told us when to come back.
  Duration backoffFor(int attempt, {Duration? retryAfter, Random? random}) {
    if (retryAfter != null) {
      return retryAfter > maxBackoff ? maxBackoff : retryAfter;
    }

    final exponent = attempt < 1 ? 0 : attempt - 1;
    final millis = initialBackoff.inMilliseconds * (1 << exponent);
    final capped =
        millis > maxBackoff.inMilliseconds ? maxBackoff.inMilliseconds : millis;

    if (!jitter) {
      return Duration(milliseconds: capped);
    }

    final source = random ?? Random();
    return Duration(milliseconds: source.nextInt(capped + 1));
  }
}

/// When a circuit breaker opens.
class CircuitBreakerPolicy {
  /// Creates a circuit breaker policy.
  const CircuitBreakerPolicy({
    this.failureThreshold = 5,
    this.failureRatio = 0.5,
    this.minimumCalls = 10,
    this.window = const Duration(seconds: 10),
    this.cooldown = const Duration(seconds: 5),
  });

  /// How many failures open the circuit, whatever the ratio is.
  final int failureThreshold;

  /// The ratio of failures that opens the circuit.
  final double failureRatio;

  /// How many calls the window needs before the ratio is looked at.
  final int minimumCalls;

  /// How long the window of the calls lasts.
  final Duration window;

  /// How long the circuit stays open before a probe is allowed.
  final Duration cooldown;

  /// Whether the breaker is never used.
  static const CircuitBreakerPolicy none = CircuitBreakerPolicy(
    failureThreshold: 0,
    failureRatio: 0,
    minimumCalls: 0,
  );
}

/// How many calls a dependency may run at the same time.
class BulkheadPolicy {
  /// Creates a bulkhead policy.
  const BulkheadPolicy({
    this.maxConcurrent = 16,
    this.maxQueue = 32,
    this.acquireTimeout = const Duration(seconds: 1),
  });

  /// How many calls run at the same time.
  final int maxConcurrent;

  /// How many calls wait for a free slot.
  final int maxQueue;

  /// How long a call waits for a free slot before it gives up.
  final Duration acquireTimeout;

  /// A policy that lets everything through.
  static const BulkheadPolicy none = BulkheadPolicy(
    maxConcurrent: 1000000,
    maxQueue: 1000000,
  );
}

/// The complete policy of a call to another service.
class DependencyPolicy {
  /// Creates a dependency policy.
  const DependencyPolicy({
    this.timeout,
    this.retry = const RetryPolicy(),
    this.circuitBreaker,
    this.bulkhead,
    this.idempotent = false,
  });

  /// How long one attempt may take.
  ///
  /// A call without a timeout is a bug, so the policy leaves the timeout to
  /// the dependency when it has none: the dependency then falls back to its
  /// own default, and never lets a call hang.
  final Duration? timeout;

  /// How a failed call is retried.
  final RetryPolicy retry;

  /// When the circuit of the dependency opens.
  final CircuitBreakerPolicy? circuitBreaker;

  /// How many calls of the dependency run at the same time.
  final BulkheadPolicy? bulkhead;

  /// Whether the call may be repeated.
  ///
  /// A call that is not idempotent is never retried, no matter what the retry
  /// policy says: repeating it could charge a customer twice.
  final bool idempotent;

  /// A copy of this policy with the given fields replaced.
  DependencyPolicy copyWith({
    Duration? timeout,
    RetryPolicy? retry,
    CircuitBreakerPolicy? circuitBreaker,
    BulkheadPolicy? bulkhead,
    bool? idempotent,
  }) =>
      DependencyPolicy(
        timeout: timeout ?? this.timeout,
        retry: retry ?? this.retry,
        circuitBreaker: circuitBreaker ?? this.circuitBreaker,
        bulkhead: bulkhead ?? this.bulkhead,
        idempotent: idempotent ?? this.idempotent,
      );
}
