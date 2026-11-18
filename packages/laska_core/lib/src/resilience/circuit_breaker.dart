/// The circuit breaker of a dependency.
///
/// The breaker stops the calls to a dependency that is failing, so a service
/// does not pile up on a dependency that cannot answer.
library;

import 'errors.dart';
import 'policy.dart';

/// The state of a circuit.
enum CircuitState {
  /// The calls go through.
  closed,

  /// The calls fail fast, until the cooldown is over.
  open,

  /// One call is allowed, to see whether the dependency recovered.
  halfOpen,
}

/// The circuit breaker of one dependency.
///
/// The breaker counts the attempts, not the calls: a call that is retried
/// three times tells more about the health of the dependency than one call
/// that failed once.
class CircuitBreaker {
  /// Creates a breaker for the dependency [dependency].
  CircuitBreaker(
    this.dependency,
    this.policy, {
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  /// Name of the dependency the breaker belongs to.
  final String dependency;

  /// When the breaker opens.
  final CircuitBreakerPolicy policy;

  final DateTime Function() _clock;
  final List<_Outcome> _outcomes = <_Outcome>[];

  CircuitState _state = CircuitState.closed;
  DateTime? _openedAt;
  bool _probeInFlight = false;

  /// The state of the breaker.
  CircuitState get state => _state;

  /// How many calls the breaker let through in the current window.
  int get callsInWindow => _outcomes.length;

  /// How many of them failed.
  int get failuresInWindow =>
      _outcomes.where((outcome) => outcome.failed).length;

  /// Whether the circuit lets a call through right now.
  bool get allowsCall {
    if (_state == CircuitState.closed) {
      return true;
    }
    if (_state == CircuitState.halfOpen) {
      return !_probeInFlight;
    }
    return _cooldownOver;
  }

  bool get _cooldownOver {
    final openedAt = _openedAt;
    if (openedAt == null) {
      return true;
    }
    return !_clock().isBefore(openedAt.add(policy.cooldown));
  }

  /// Runs [operation] through the breaker.
  ///
  /// Throws [CircuitOpenException] when the circuit is open, so the caller
  /// fails fast instead of waiting for a timeout.
  Future<T> call<T>(Future<T> Function() operation) async {
    if (_state == CircuitState.open) {
      if (!_cooldownOver) {
        throw CircuitOpenException(dependency, _retryAfter);
      }
      _state = CircuitState.halfOpen;
      _probeInFlight = false;
    }

    if (_state == CircuitState.halfOpen) {
      if (_probeInFlight) {
        throw CircuitOpenException(dependency, _retryAfter);
      }
      _probeInFlight = true;
    }

    try {
      final result = await operation();
      recordSuccess();
      return result;
    } catch (error) {
      recordFailure();
      rethrow;
    }
  }

  /// Records a call that worked.
  void recordSuccess() {
    if (_state == CircuitState.halfOpen) {
      _close();
      return;
    }
    _outcomes.add(_Outcome(_clock(), failed: false));
    _prune();
  }

  /// Records a call that failed.
  void recordFailure() {
    if (_state == CircuitState.halfOpen) {
      _open();
      return;
    }

    _outcomes.add(_Outcome(_clock(), failed: true));
    _prune();

    final failures = failuresInWindow;
    if (failures < policy.failureThreshold) {
      return;
    }
    if (_outcomes.length < policy.minimumCalls) {
      return;
    }
    if (failures / _outcomes.length < policy.failureRatio) {
      return;
    }
    _open();
  }

  /// How long the caller should wait before trying again.
  Duration get _retryAfter {
    final openedAt = _openedAt;
    if (openedAt == null) {
      return Duration.zero;
    }
    final left = openedAt.add(policy.cooldown).difference(_clock());
    return left.isNegative ? Duration.zero : left;
  }

  void _open() {
    _state = CircuitState.open;
    _openedAt = _clock();
    _probeInFlight = false;
  }

  void _close() {
    _state = CircuitState.closed;
    _openedAt = null;
    _probeInFlight = false;
    _outcomes.clear();
  }

  void _prune() {
    final limit = _clock().subtract(policy.window);
    _outcomes.removeWhere((outcome) => outcome.at.isBefore(limit));
  }
}

/// The outcome of one call in the window of a breaker.
class _Outcome {
  _Outcome(this.at, {required this.failed});

  final DateTime at;
  final bool failed;
}
