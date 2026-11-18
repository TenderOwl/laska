/// The small helpers of the bytes of the authentication.
///
/// The tokens of a service travel as base64url text, and the comparison of a
/// signature must not tell the attacker how much of it was right. Both helpers
/// live here, so every part of the authentication uses the same ones.
library;

import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

/// The [count] random bytes of the operating system.
///
/// The bytes come from the cryptographic source of the platform, so they are
/// not guessable.
Uint8List randomBytes(int count, [Random? random]) {
  if (count < 0) {
    throw ArgumentError.value(count, 'count', 'The count must not be negative');
  }
  final source = random ?? Random.secure();
  return Uint8List.fromList(
    List<int>.generate(count, (_) => source.nextInt(256)),
  );
}

/// The base64url encoding of [bytes], without the padding.
///
/// The padding is dropped, because the tokens of a service are read as text
/// and the padding only adds noise.
String base64UrlEncode(List<int> bytes) =>
    base64Url.encode(bytes).replaceAll('=', '');

/// Decodes the base64url [text].
///
/// The padding may be missing, as it is in a token. Throws a [FormatException]
/// when the text is not base64url.
List<int> base64UrlDecode(String text) {
  if (text.isEmpty) {
    return const <int>[];
  }
  try {
    return base64Url.decode(base64Url.normalize(text));
  } on FormatException {
    throw const FormatException('The value is not valid base64url');
  } on ArgumentError {
    throw const FormatException('The value is not valid base64url');
  }
}

/// Compares [left] and [right] without telling how much of them is equal.
///
/// The comparison takes the same time whatever the values are, so an attacker
/// cannot guess a secret one byte at a time.
bool constantTimeEquals(List<int> left, List<int> right) {
  var difference = left.length ^ right.length;
  final length = left.length < right.length ? left.length : right.length;

  for (var index = 0; index < length; index++) {
    difference |= left[index] ^ right[index];
  }

  return difference == 0;
}

/// The bytes of [value], big-endian and without a leading zero.
///
/// The bytes of zero are empty, as the number zero has no digits.
Uint8List bigIntToBytes(BigInt value) {
  if (value == BigInt.zero) {
    return Uint8List(0);
  }

  final hex = value.toRadixString(16);
  final padded = hex.length.isOdd ? '0$hex' : hex;
  final bytes = Uint8List(padded.length ~/ 2);

  for (var index = 0; index < bytes.length; index++) {
    bytes[index] =
        int.parse(padded.substring(index * 2, index * 2 + 2), radix: 16);
  }

  return bytes;
}

/// The number of the bytes.
BigInt bigIntFromBytes(List<int> bytes) {
  var result = BigInt.zero;
  for (final byte in bytes) {
    result = (result << 8) | BigInt.from(byte);
  }
  return result;
}
