/// The cache of a service.
///
/// The cache is a seam: [CacheStore] is the interface, the runtime ships an
/// implementation that keeps the values in the memory of the process, and a
/// service that needs a shared cache writes its own store — Redis, Memcached,
/// the database — behind the same interface.
library;

import 'dart:collection';

/// A store that keeps the values of a cache.
///
/// The store is the mechanism, not the policy: it holds a value under a key
/// until the value expires, and it forgets a value when it is deleted. The
/// policy — how long a value lives, what is worth keeping — belongs to the
/// [Cache] that sits on top of it.
abstract class CacheStore {
  /// Creates a store.
  const CacheStore();

  /// Reads the value stored under [key].
  ///
  /// Returns null when the key is unknown, when the value expired or when the
  /// value is not a [T]. A null value is a miss: the cache does not keep nulls.
  Future<T?> read<T>(String key);

  /// Stores [value] under [key].
  ///
  /// A [ttl] of null means the value does not expire. A store may keep the
  /// value longer than the ttl asks for — a store that cannot expire a value
  /// on its own keeps it until it is deleted.
  Future<void> write<T>(String key, T value, {Duration? ttl});

  /// Removes the value stored under [key].
  ///
  /// Removing a key that is unknown is not an error.
  Future<void> delete(String key);

  /// Removes every value of the store.
  Future<void> clear();
}

/// A cache store that keeps the values in the memory of the process.
///
/// The store is the default one of the runtime: a worker is a process of its
/// own, so the values of the cache belong to the worker that wrote them. The
/// store forgets the least recently used value when it grows past
/// [maxEntries], and it forgets a value when its ttl is over.
class MemoryCacheStore implements CacheStore {
  /// Creates a store that keeps at most [maxEntries] values.
  ///
  /// The [clock] is the source of the time; a test replaces it to move the
  /// time of the store without waiting.
  MemoryCacheStore({
    this.maxEntries = 1024,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now {
    if (maxEntries < 1) {
      throw ArgumentError.value(maxEntries, 'maxEntries', 'Must be positive');
    }
  }

  /// How many values the store keeps at most.
  ///
  /// When the store grows past the limit, the least recently used value is
  /// forgotten.
  final int maxEntries;

  final DateTime Function() _clock;

  /// The values of the store, the least recently used first.
  final LinkedHashMap<String, _CacheEntry> _entries =
      LinkedHashMap<String, _CacheEntry>();

  /// How many values the store holds.
  int get length => _entries.length;

  /// The keys the store holds, the least recently used first.
  List<String> get keys => List<String>.unmodifiable(_entries.keys);

  @override
  Future<T?> read<T>(String key) async {
    final entry = _entries.remove(key);
    if (entry == null) {
      return null;
    }
    if (entry.isExpired(_clock())) {
      return null;
    }
    // The value was read, so it becomes the most recently used one.
    _entries[key] = entry;
    final value = entry.value;
    return value is T ? value : null;
  }

  @override
  Future<void> write<T>(String key, T value, {Duration? ttl}) async {
    _entries.remove(key);
    _entries[key] = _CacheEntry(
      value,
      ttl == null ? null : _clock().add(ttl),
    );
    while (_entries.length > maxEntries) {
      _entries.remove(_entries.keys.first);
    }
  }

  @override
  Future<void> delete(String key) async {
    _entries.remove(key);
  }

  @override
  Future<void> clear() async {
    _entries.clear();
  }
}

/// The cache of a service.
///
/// The cache is the face of a [CacheStore]: it reads and writes the values,
/// it holds the time they live and it keeps one loader per key, so a burst of
/// calls that miss the cache loads the value once instead of once per call.
class Cache {
  /// Creates a cache over [store].
  ///
  /// The [defaultTtl] is how long a value lives when the caller does not say
  /// how long it should live.
  Cache(
    this.store, {
    this.defaultTtl = const Duration(minutes: 5),
  });

  /// Creates a cache that keeps the values in the memory of the process.
  Cache.memory({
    int maxEntries = 1024,
    Duration defaultTtl = const Duration(minutes: 5),
  }) : this(
          MemoryCacheStore(maxEntries: maxEntries),
          defaultTtl: defaultTtl,
        );

  /// The store holding the values.
  final CacheStore store;

  /// How long a value lives when the caller does not say.
  final Duration defaultTtl;

  final Map<String, Future<Object?>> _pending = <String, Future<Object?>>{};

  /// The keys whose value is being loaded right now.
  ///
  /// A test asserts that a burst of calls loads the value once.
  int get pending => _pending.length;

  /// Reads the value stored under [key].
  Future<T?> get<T>(String key) => store.read<T>(key);

  /// Stores [value] under [key].
  ///
  /// The value lives for [ttl], or for [defaultTtl] when the caller does not
  /// say. A store that should keep the value until it is deleted is reached
  /// through [store] directly.
  Future<void> put<T>(String key, T value, {Duration? ttl}) =>
      store.write<T>(key, value, ttl: ttl ?? defaultTtl);

  /// Removes the value stored under [key].
  Future<void> delete(String key) => store.delete(key);

  /// Removes every value of the cache.
  Future<void> clear() => store.clear();

  /// Returns the value stored under [key], loading it when it is missing.
  ///
  /// The [loader] runs only when the value is not cached. When a burst of
  /// calls asks for the same key at the same time, the loader runs once and
  /// the calls wait for it: the cache does not let a cold key fall over the
  /// service that holds it. The error of the loader reaches every caller that
  /// waits for it, and the value is not cached.
  ///
  /// The value is written for [ttl], or for [defaultTtl] when the caller does
  /// not say.
  Future<T> remember<T>(
    String key,
    Future<T> Function() loader, {
    Duration? ttl,
  }) async {
    final cached = await store.read<T>(key);
    if (cached != null) {
      return cached;
    }

    final pending = _pending[key];
    if (pending != null) {
      final value = await pending;
      return value as T;
    }

    final future = loader();
    _pending[key] = future;
    try {
      final value = await future;
      await store.write<T>(key, value, ttl: ttl ?? defaultTtl);
      return value;
    } finally {
      _pending.remove(key);
    }
  }
}

/// One value of the memory store.
class _CacheEntry {
  _CacheEntry(this.value, this.expiresAt);

  final Object? value;
  final DateTime? expiresAt;

  bool isExpired(DateTime now) {
    final expiresAt = this.expiresAt;
    if (expiresAt == null) {
      return false;
    }
    return !now.isBefore(expiresAt);
  }
}
