/// The bulkhead of a dependency.
///
/// The bulkhead limits how many calls of a dependency run at the same time, so
/// one slow dependency cannot use up the whole process.
library;

import 'dart:async';

import 'errors.dart';
import 'policy.dart';

/// The bulkhead of one dependency.
class Bulkhead {
  /// Creates a bulkhead for the dependency [dependency].
  Bulkhead(this.dependency, this.policy);

  /// Name of the dependency the bulkhead belongs to.
  final String dependency;

  /// How many calls may run at the same time.
  final BulkheadPolicy policy;

  final List<Completer<void>> _waiting = <Completer<void>>[];
  int _active = 0;

  /// How many calls run right now.
  int get active => _active;

  /// How many calls wait for a free slot.
  int get waiting => _waiting.length;

  /// Runs [body] once a slot is free.
  ///
  /// Throws [BulkheadFullException] when the bulkhead is full and the wait
  /// times out.
  Future<T> run<T>(Future<T> Function() body) async {
    await acquire();
    try {
      return await body();
    } finally {
      release();
    }
  }

  /// Takes a slot of the bulkhead.
  Future<void> acquire() async {
    if (_active < policy.maxConcurrent) {
      _active++;
      return;
    }

    if (_waiting.length >= policy.maxQueue) {
      throw BulkheadFullException(dependency);
    }

    final completer = Completer<void>();
    _waiting.add(completer);

    try {
      await completer.future.timeout(policy.acquireTimeout);
    } on TimeoutException {
      if (_waiting.remove(completer)) {
        throw BulkheadFullException(dependency);
      }
      // The slot was handed over while the wait was running, so it is given
      // back instead of being lost.
      release();
      throw BulkheadFullException(dependency);
    }
  }

  /// Gives a slot of the bulkhead back.
  void release() {
    while (_waiting.isNotEmpty) {
      final next = _waiting.removeAt(0);
      if (!next.isCompleted) {
        next.complete();
        return;
      }
    }
    _active--;
  }
}
