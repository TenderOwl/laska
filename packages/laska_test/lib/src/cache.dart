import 'package:laska_core/laska_core.dart';

/// A cache store that keeps the values in memory and records the calls.
///
/// The fake lets a test assert what the service cached: which keys were read,
/// which ones were written, how many reads were a hit and how many were a
/// miss. The values do not expire: the fake is about the calls of the
/// service, not about the time.
///
/// Set [error] to make every call of the store fail, so a test covers the
/// service that survives a broken cache.
class FakeCacheStore implements CacheStore {
  /// Creates a store holding [values].
  FakeCacheStore({Map<String, Object?>? values})
      : _values = <String, Object?>{...?values};

  final Map<String, Object?> _values;

  /// The keys that were read, in the order they were read.
  final List<String> reads = <String>[];

  /// The keys that were written, in the order they were written.
  final List<String> writes = <String>[];

  /// The keys that were deleted, in the order they were deleted.
  final List<String> deletes = <String>[];

  /// The time to live every value was written with, by the key it belongs to.
  final Map<String, Duration?> ttls = <String, Duration?>{};

  /// How many times the store was cleared.
  int clears = 0;

  /// How many reads found the value.
  int hits = 0;

  /// How many reads did not find the value.
  int misses = 0;

  /// When it is set, every call of the store throws it.
  Object? error;

  /// The values the store holds.
  Map<String, Object?> get values => Map<String, Object?>.unmodifiable(_values);

  @override
  Future<T?> read<T>(String key) async {
    _fail();
    reads.add(key);
    final value = _values[key];
    if (value is T) {
      hits++;
      return value;
    }
    misses++;
    return null;
  }

  @override
  Future<void> write<T>(String key, T value, {Duration? ttl}) async {
    _fail();
    writes.add(key);
    ttls[key] = ttl;
    _values[key] = value;
  }

  @override
  Future<void> delete(String key) async {
    _fail();
    deletes.add(key);
    _values.remove(key);
  }

  @override
  Future<void> clear() async {
    _fail();
    clears++;
    _values.clear();
  }

  void _fail() {
    final failure = error;
    if (failure != null) {
      throw failure;
    }
  }
}
