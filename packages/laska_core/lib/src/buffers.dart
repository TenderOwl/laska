/// The buffers of the runtime.
///
/// The bodies of the requests are read into a buffer that comes from a pool
/// and goes back to it when the request is done, so a service that answers
/// many requests does not build a buffer for every one of them.
library;

import 'dart:typed_data';

/// A pool of byte buffers.
///
/// The pool keeps a few buffers and hands them out again. A buffer that is
/// bigger than [maxSize] is dropped, so a body that is huge does not keep its
/// memory for ever.
class BufferPool {
  /// Creates a pool.
  ///
  /// The pool keeps at most [maxBuffers] buffers, and no buffer bigger than
  /// [maxSize] bytes.
  BufferPool({
    this.maxBuffers = 32,
    this.maxSize = 64 * 1024,
  });

  /// The number of buffers the pool keeps.
  final int maxBuffers;

  /// The size of the biggest buffer the pool keeps.
  final int maxSize;

  final List<Uint8List> _buffers = <Uint8List>[];

  /// The number of buffers the pool holds right now.
  int get length => _buffers.length;

  /// Takes a buffer of at least [size] bytes out of the pool.
  ///
  /// The pool is empty or holds no buffer that is big enough, so a new buffer
  /// is built.
  Uint8List take(int size) {
    for (var index = _buffers.length - 1; index >= 0; index--) {
      final buffer = _buffers.removeAt(index);
      if (buffer.length >= size) {
        return buffer;
      }
    }
    return Uint8List(size < 64 ? 64 : size);
  }

  /// Gives [buffer] back to the pool.
  void give(Uint8List buffer) {
    if (buffer.length > maxSize || _buffers.length >= maxBuffers) {
      return;
    }
    _buffers.add(buffer);
  }
}

/// The buffer that reads the body of a request.
///
/// The buffer grows as the body arrives and goes back to the pool when the
/// body was read.
class BodyBuffer {
  /// Creates a buffer that takes its bytes from [pool].
  BodyBuffer(this._pool);

  /// The pool the buffer comes from and goes back to.
  final BufferPool _pool;

  Uint8List? _bytes;
  int _length = 0;

  /// The number of bytes that were read.
  int get length => _length;

  /// Adds [chunk] to the body.
  void add(List<int> chunk) {
    if (chunk.isEmpty) {
      return;
    }

    final bytes = _bytes;
    if (bytes == null || _length + chunk.length > bytes.length) {
      _grow(_length + chunk.length);
    }
    _bytes!.setRange(_length, _length + chunk.length, chunk);
    _length += chunk.length;
  }

  /// The bytes of the body.
  ///
  /// The bytes are a view of the buffer, so they are only valid until the
  /// buffer is released.
  Uint8List take() {
    final bytes = _bytes;
    if (bytes == null) {
      return Uint8List(0);
    }
    return Uint8List.sublistView(bytes, 0, _length);
  }

  /// Gives the buffer back to the pool.
  ///
  /// The buffer is released when the bytes that were taken are not needed
  /// any more.
  void release() {
    final bytes = _bytes;
    _bytes = null;
    _length = 0;
    if (bytes != null) {
      _pool.give(bytes);
    }
  }

  /// Grows the buffer to hold [size] bytes.
  void _grow(int size) {
    final current = _bytes;
    final grown = Uint8List(size < 64 ? 64 : size);

    if (current != null) {
      grown.setRange(0, _length, current);
      // The buffer that was too small goes back to the pool.
      _pool.give(current);
    }

    _bytes = grown;
  }
}
