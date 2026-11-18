/// The digests of SHA-2 in the shape the signers of PointyCastle expect them.
///
/// The hash itself comes from `package:crypto`. The adapter only gives it the
/// shape a signer wants, so one implementation of the hash serves both the
/// HMAC of the tokens and the signatures of the asymmetric keys.
library;

import 'dart:typed_data';

import 'package:crypto/crypto.dart' hide Digest;
import 'package:pointycastle/api.dart';

/// A digest of SHA-2 for the signers of PointyCastle.
///
/// The digest keeps the bytes it is given, so the signers may feed it in
/// pieces.
class Sha2Digest implements Digest {
  /// Creates the digest of [algorithmName].
  Sha2Digest(
    this.algorithmName,
    this._hash,
    this.digestSize,
    this.byteLength,
  );

  /// The digest of SHA-256.
  factory Sha2Digest.sha256() => Sha2Digest('SHA-256', sha256, 32, 64);

  /// The digest of SHA-384.
  factory Sha2Digest.sha384() => Sha2Digest('SHA-384', sha384, 48, 128);

  /// The digest of SHA-512.
  factory Sha2Digest.sha512() => Sha2Digest('SHA-512', sha512, 64, 128);

  final Hash _hash;

  final BytesBuilder _buffer = BytesBuilder(copy: false);

  @override
  final String algorithmName;

  @override
  final int digestSize;

  @override
  final int byteLength;

  @override
  void reset() => _buffer.clear();

  @override
  Uint8List process(Uint8List data) =>
      Uint8List.fromList(_hash.convert(data).bytes);

  @override
  void updateByte(int inp) => _buffer.addByte(inp);

  @override
  void update(Uint8List inp, int inpOff, int len) =>
      _buffer.add(inp.sublist(inpOff, inpOff + len));

  @override
  int doFinal(Uint8List out, int outOff) {
    final digest = _hash.convert(_buffer.toBytes()).bytes;
    out.setRange(outOff, outOff + digest.length, digest);
    _buffer.clear();
    return digest.length;
  }
}
