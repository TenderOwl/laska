/// The rate limiting of the calls of a service.
///
/// The limiter protects a service from a caller that asks for too much: the
/// caller gets a `429` and a hint of when it may come back, instead of a
/// queue that grows until the service falls over.
library;

/// The limiter of the calls of a service.
///
/// The limiter is a token bucket per key: every key has a bucket that is
/// filled with [limit] tokens every [window], and every call takes one token.
/// A caller that runs out of tokens waits for the bucket to be filled again.
class RateLimiter {
  /// Creates a limiter.
  ///
  /// The [clock] is injected, so a test can move the time without waiting.
  RateLimiter({
    this.limit = 100,
    this.window = const Duration(minutes: 1),
    this.maxKeys = 10000,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  /// How many calls a key may make per window.
  final int limit;

  /// The window the calls are counted in.
  final Duration window;

  /// How many keys the limiter keeps at most.
  ///
  /// The oldest key is dropped when the limiter is full, so an attacker that
  /// sends a request per random key cannot grow the memory of the service.
  final int maxKeys;

  final DateTime Function() _clock;
  final Map<String, _Bucket> _buckets = <String, _Bucket>{};

  /// The number of keys the limiter holds.
  int get keys => _buckets.length;

  /// Whether the key may make a call right now.
  ///
  /// The call takes a token of the key, so a call that is allowed counts.
  bool allow(String key) => consume(key) == null;

  /// Takes a token of the key, or returns how long the key has to wait.
  ///
  /// Returns `null` when the call is allowed.
  Duration? consume(String key) {
    final now = _clock();
    final bucket = _buckets.putIfAbsent(key, () {
      if (_buckets.length >= maxKeys) {
        _buckets.remove(_buckets.keys.first);
      }
      return _Bucket(tokens: limit.toDouble(), updatedAt: now);
    });

    final elapsed = now.difference(bucket.updatedAt);
    if (elapsed > Duration.zero) {
      final refill = elapsed.inMicroseconds / window.inMicroseconds * limit;
      bucket.tokens = (bucket.tokens + refill).clamp(0, limit.toDouble());
      bucket.updatedAt = now;
    }

    if (bucket.tokens >= 1) {
      bucket.tokens -= 1;
      return null;
    }

    final missing = 1 - bucket.tokens;
    final wait = Duration(
      microseconds: (missing / limit * window.inMicroseconds).round(),
    );
    return wait;
  }

  /// How many calls the key may still make in the current window.
  int remaining(String key) {
    final bucket = _buckets[key];
    if (bucket == null) {
      return limit;
    }
    return bucket.tokens.floor();
  }

  /// How long the key has to wait before its next call.
  ///
  /// Returns `Duration.zero` when the key may call right now.
  Duration retryAfter(String key) {
    final bucket = _buckets[key];
    if (bucket == null) {
      return Duration.zero;
    }
    final missing = 1 - bucket.tokens;
    if (missing <= 0) {
      return Duration.zero;
    }
    return Duration(
      microseconds: (missing / limit * window.inMicroseconds).round(),
    );
  }

  /// Forgets the bucket of the key.
  void forget(String key) => _buckets.remove(key);

  /// Forgets every bucket.
  void reset() => _buckets.clear();
}

/// The tokens of one key.
class _Bucket {
  _Bucket({required this.tokens, required this.updatedAt});

  double tokens;
  DateTime updatedAt;
}
