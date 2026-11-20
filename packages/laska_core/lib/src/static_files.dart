import 'dart:io';

import 'errors.dart';
import 'request.dart';
import 'response.dart';

/// The content types the static files are served with.
///
/// The map is keyed by the extension of the file, in lower case and without
/// the dot. A file with an extension the map does not hold is served as
/// `application/octet-stream`.
const Map<String, String> staticContentTypes = <String, String>{
  'html': 'text/html; charset=utf-8',
  'htm': 'text/html; charset=utf-8',
  'css': 'text/css; charset=utf-8',
  'js': 'text/javascript; charset=utf-8',
  'mjs': 'text/javascript; charset=utf-8',
  'json': 'application/json; charset=utf-8',
  'map': 'application/json; charset=utf-8',
  'svg': 'image/svg+xml',
  'png': 'image/png',
  'jpg': 'image/jpeg',
  'jpeg': 'image/jpeg',
  'gif': 'image/gif',
  'webp': 'image/webp',
  'avif': 'image/avif',
  'bmp': 'image/bmp',
  'ico': 'image/vnd.microsoft.icon',
  'txt': 'text/plain; charset=utf-8',
  'md': 'text/markdown; charset=utf-8',
  'csv': 'text/csv; charset=utf-8',
  'xml': 'application/xml; charset=utf-8',
  'pdf': 'application/pdf',
  'wasm': 'application/wasm',
  'zip': 'application/zip',
  'gz': 'application/gzip',
  'mp4': 'video/mp4',
  'webm': 'video/webm',
  'mp3': 'audio/mpeg',
  'ogg': 'audio/ogg',
  'wav': 'audio/wav',
  'woff': 'font/woff',
  'woff2': 'font/woff2',
  'ttf': 'font/ttf',
  'otf': 'font/otf',
};

/// The content type of the file with the [extension].
///
/// The extension is the one of the file without the dot, e.g. `css`. The
/// value is `null` when the runtime does not know the extension, so the
/// caller can fall back to `application/octet-stream`.
String? contentTypeForExtension(String extension) =>
    staticContentTypes[extension.toLowerCase()];

/// Serves the files of a directory.
///
/// The class is what [Laska.staticFiles] registers, and a service may use it
/// on its own when it mounts the files of a directory by hand.
///
/// The files are served with the validators of the cache — an `ETag` and a
/// `Last-Modified` — so a browser asks for a file again only when it changed.
class StaticFiles {
  /// Creates a handler of the files of [directory].
  StaticFiles({
    required this.directory,
    this.fallback,
    this.maxAge,
    this.index = 'index.html',
    this.headers = const <String, String>{},
  });

  /// The directory the files are read from.
  final String directory;

  /// The file served when the requested one is missing.
  ///
  /// A single page application is served this way: every path that does not
  /// name a file of the directory answers with the same HTML, and the router
  /// of the application takes it from there.
  final String? fallback;

  /// How long a browser may keep the file.
  ///
  /// The value is written in the `Cache-Control` header of the answer. The
  /// header is left out when the value is `null`.
  final Duration? maxAge;

  /// The file served when the request points at a directory.
  final String index;

  /// Extra headers written to every answer of the handler.
  final Map<String, String> headers;

  /// Answers the [request] with the file it points at.
  ///
  /// The file is looked up in the directory of the handler. The path of the
  /// request is decoded first, and a path that points outside of the
  /// directory is refused.
  ///
  /// Throws [HttpException] with the status 404 when no file matches and
  /// there is no fallback, and with the status 400 when the path of the
  /// request is not encoded correctly.
  Future<Response> handle(Request request) async {
    final segments = _segmentsOf(request.params['*'] ?? '');

    final file = await _fileOf(segments);
    if (file != null) {
      return await _respond(request, file);
    }

    final fallbackFile = await _fallbackFile();
    if (fallbackFile != null) {
      return await _respond(request, fallbackFile);
    }

    throw HttpException(404, 'No static file matches ${request.path}.');
  }

  /// The file of the directory the [segments] point at.
  ///
  /// The value is `null` when there is no such file, when the path points
  /// outside of the directory or when the directory does not exist.
  Future<File?> _fileOf(List<String> segments) async {
    final root = Directory(directory);
    if (!await root.exists()) {
      return null;
    }

    File candidate;
    if (segments.isEmpty) {
      // The request points at the directory of the root itself.
      candidate = File(_join(root.path, <String>[index]));
    } else {
      final path = _join(root.path, segments);

      FileStat stat;
      try {
        stat = await FileStat.stat(path);
      } on FileSystemException {
        return null;
      }

      if (stat.type == FileSystemEntityType.directory) {
        candidate = File(_join(path, <String>[index]));
      } else if (stat.type == FileSystemEntityType.file) {
        candidate = File(path);
      } else {
        return null;
      }
    }

    if (!await candidate.exists()) {
      return null;
    }
    final stat = await candidate.stat();
    if (stat.type != FileSystemEntityType.file) {
      return null;
    }

    if (!await _isInside(root, candidate)) {
      return null;
    }
    return candidate;
  }

  /// The file served when the requested one is missing.
  Future<File?> _fallbackFile() async {
    final fallback = this.fallback;
    if (fallback == null) {
      return null;
    }
    return await _fileOf(_segmentsOf(fallback));
  }

  /// Whether the [candidate] is inside of the [root].
  ///
  /// The paths are resolved before they are compared, so a link inside of the
  /// directory that points outside of it is refused as well.
  Future<bool> _isInside(Directory root, File candidate) async {
    String rootPath;
    String candidatePath;
    try {
      rootPath = await root.resolveSymbolicLinks();
      candidatePath = await candidate.resolveSymbolicLinks();
    } on FileSystemException {
      return false;
    }
    return _contains(rootPath, candidatePath);
  }

  /// Whether the [path] is inside of the [root].
  static bool _contains(String root, String path) {
    var parent = root;
    var child = path;

    // The paths of Windows do not know the case, so the comparison of them
    // does not either.
    if (Platform.isWindows) {
      parent = parent.toLowerCase();
      child = child.toLowerCase();
    }

    if (!parent.endsWith(Platform.pathSeparator)) {
      parent = '$parent${Platform.pathSeparator}';
    }
    return child.startsWith(parent);
  }

  /// The segments of the path of the file.
  ///
  /// The path of the request is not decoded by the server, so the segments are
  /// decoded here. A segment that points outside of the directory is refused.
  static List<String> _segmentsOf(String remainder) {
    final segments = <String>[];
    for (final raw in remainder.split('/')) {
      if (raw.isEmpty) {
        continue;
      }

      final String decoded;
      try {
        decoded = Uri.decodeComponent(raw);
      } on ArgumentError {
        throw HttpException(
          400,
          'The path of the file is not encoded correctly.',
        );
      } on FormatException {
        throw HttpException(
          400,
          'The path of the file is not encoded correctly.',
        );
      }

      if (decoded == '.') {
        continue;
      }
      if (_pointsOutside(decoded)) {
        throw HttpException(
          404,
          'The path of the file points outside of the directory.',
        );
      }
      segments.add(decoded);
    }
    return segments;
  }

  /// Whether the [segment] points outside of the directory.
  static bool _pointsOutside(String segment) {
    if (segment == '..') {
      return true;
    }
    if (segment.contains('/') || segment.contains('\\')) {
      return true;
    }
    if (segment.contains('\\u0000')) {
      return true;
    }
    // A colon starts a drive on Windows, e.g. `C:`.
    if (Platform.isWindows && segment.contains(':')) {
      return true;
    }
    return false;
  }

  /// The path of the file of the [segments] inside of the [root].
  static String _join(String root, List<String> segments) {
    if (segments.isEmpty) {
      return root;
    }
    return '$root${Platform.pathSeparator}'
        '${segments.join(Platform.pathSeparator)}';
  }

  /// Answers the [request] with the [file].
  Future<Response> _respond(Request request, File file) async {
    final stat = await file.stat();
    final etag = _etagOf(stat);
    final modified = stat.modified;

    final headers = <String, String>{
      'etag': etag,
      'last-modified': formatHttpDate(modified),
      'x-content-type-options': 'nosniff',
      if (maxAge != null)
        'cache-control': 'public, max-age=${maxAge!.inSeconds}',
      ...this.headers,
    };

    if (_isFresh(
      request,
      etag,
      modified,
      request.header('if-none-match'),
      request.header('if-modified-since'),
    )) {
      return Response(status: 304, headers: headers);
    }

    final contentType = contentTypeForExtension(_extensionOf(file.path)) ??
        'application/octet-stream';

    if (request.method == 'HEAD') {
      return Response(
        status: 200,
        headers: <String, String>{
          ...headers,
          'content-type': contentType,
          'content-length': '${stat.size}',
        },
      );
    }

    final bytes = await file.readAsBytes();
    return Response.bytes(bytes, headers: <String, String>{
      ...headers,
      'content-type': contentType,
    });
  }

  /// Whether the browser that sent the [request] already holds the file.
  ///
  /// The `ETag` of the request wins over its date: the `If-None-Match`
  /// header is the stronger of the two validators.
  static bool _isFresh(
    Request request,
    String etag,
    DateTime modified,
    String? ifNoneMatch,
    String? ifModifiedSince,
  ) {
    if (ifNoneMatch != null && ifNoneMatch.trim().isNotEmpty) {
      return _matchesEtag(ifNoneMatch, etag);
    }

    if (ifModifiedSince != null) {
      final since = parseHttpDate(ifModifiedSince);
      if (since != null) {
        // The dates are compared in seconds, because the header holds one.
        return modified.millisecondsSinceEpoch ~/ 1000 <=
            since.millisecondsSinceEpoch ~/ 1000;
      }
    }
    return false;
  }

  /// Whether the [header] holds the [etag].
  ///
  /// The comparison is the weak one of RFC 9110: a weak validator of the
  /// request matches the strong validator of the file.
  static bool _matchesEtag(String header, String etag) {
    for (final raw in header.split(',')) {
      var value = raw.trim();
      if (value == '*') {
        return true;
      }
      if (value.startsWith('W/')) {
        value = value.substring(2);
      }
      if (value == etag) {
        return true;
      }
    }
    return false;
  }

  /// The validator of the file with the [stat].
  static String _etagOf(FileStat stat) => '"${stat.size.toRadixString(16)}-'
      '${stat.modified.millisecondsSinceEpoch.toRadixString(16)}"';

  /// The extension of the file with the [path], without the dot.
  static String _extensionOf(String path) {
    final name = path.split(Platform.pathSeparator).last;
    final dot = name.lastIndexOf('.');
    if (dot <= 0 || dot == name.length - 1) {
      return '';
    }
    return name.substring(dot + 1);
  }
}

/// The path of the route that serves the files under [prefix].
///
/// The path holds a wildcard, so the router hands the rest of the path of
/// the request to the handler.
String staticRoutePath(String prefix) {
  var base = prefix.trim();
  if (base.isEmpty || base == '/') {
    return '/*';
  }
  if (!base.startsWith('/')) {
    base = '/$base';
  }
  while (base.length > 1 && base.endsWith('/')) {
    base = base.substring(0, base.length - 1);
  }
  return '$base/*';
}

const List<String> _weekdays = <String>[
  'Mon',
  'Tue',
  'Wed',
  'Thu',
  'Fri',
  'Sat',
  'Sun',
];

const List<String> _months = <String>[
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];

final RegExp _imfDate = RegExp(
  r'^[A-Za-z]{3}, (\d{2}) ([A-Za-z]{3}) (\d{4}) '
  r'(\d{2}):(\d{2}):(\d{2}) GMT$',
);

final RegExp _rfc850Date = RegExp(
  r'^[A-Za-z]+, (\d{2})-([A-Za-z]{3})-(\d{2,4}) '
  r'(\d{2}):(\d{2}):(\d{2}) GMT$',
);

final RegExp _asctimeDate = RegExp(
  r'^[A-Za-z]{3} ([A-Za-z]{3}) ([ \d]\d) '
  r'(\d{2}):(\d{2}):(\d{2}) (\d{4})$',
);

/// Formats [time] as an HTTP date.
///
/// The format is the one of RFC 9110: `Sun, 06 Nov 1994 08:49:37 GMT`.
String formatHttpDate(DateTime time) {
  final utc = time.toUtc();
  final day = _weekdays[utc.weekday - 1];
  final month = _months[utc.month - 1];
  final dayOfMonth = utc.day.toString().padLeft(2, '0');
  final hour = utc.hour.toString().padLeft(2, '0');
  final minute = utc.minute.toString().padLeft(2, '0');
  final second = utc.second.toString().padLeft(2, '0');
  return '$day, $dayOfMonth $month ${utc.year} '
      '$hour:$minute:$second GMT';
}

/// Parses an HTTP date.
///
/// The three formats of RFC 9110 are read: the one of IMF-fixdate, the one of
/// RFC 850 and the one of asctime. The value is `null` when the runtime does
/// not know the format or when the date is not a real one.
DateTime? parseHttpDate(String value) {
  final trimmed = value.trim();

  final imf = _imfDate.firstMatch(trimmed);
  if (imf != null) {
    return _dateOf(
      year: int.parse(imf.group(3)!),
      month: _months.indexOf(imf.group(2)!),
      day: int.parse(imf.group(1)!),
      hour: int.parse(imf.group(4)!),
      minute: int.parse(imf.group(5)!),
      second: int.parse(imf.group(6)!),
    );
  }

  final rfc850 = _rfc850Date.firstMatch(trimmed);
  if (rfc850 != null) {
    var year = int.parse(rfc850.group(3)!);
    if (year < 100) {
      year += year < 70 ? 2000 : 1900;
    }
    return _dateOf(
      year: year,
      month: _months.indexOf(rfc850.group(2)!),
      day: int.parse(rfc850.group(1)!),
      hour: int.parse(rfc850.group(4)!),
      minute: int.parse(rfc850.group(5)!),
      second: int.parse(rfc850.group(6)!),
    );
  }

  final asctime = _asctimeDate.firstMatch(trimmed);
  if (asctime != null) {
    return _dateOf(
      year: int.parse(asctime.group(6)!),
      month: _months.indexOf(asctime.group(1)!),
      day: int.parse(asctime.group(2)!.trim()),
      hour: int.parse(asctime.group(3)!),
      minute: int.parse(asctime.group(4)!),
      second: int.parse(asctime.group(5)!),
    );
  }

  return null;
}

/// The date of the parts of an HTTP date.
///
/// The value is `null` when the month is not known or when the day is not a
/// real one.
DateTime? _dateOf({
  required int year,
  required int month,
  required int day,
  required int hour,
  required int minute,
  required int second,
}) {
  if (month < 0) {
    return null;
  }
  final date = DateTime.utc(year, month + 1, day, hour, minute, second);
  // The date is built out of its parts, so a day of the month that does not
  // exist rolls over into the next month. The date is refused when it does.
  if (date.day != day || date.month != month + 1) {
    return null;
  }
  return date;
}
