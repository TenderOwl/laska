/// The sessions of the users of a service.
///
/// A session is a small piece of state that lives on the server: the user is
/// logged in, the session holds what the service remembers about them. The
/// session is identified by a random id that travels in a cookie.
library;

import 'dart:async';
import 'dart:math';

/// A session of a user.
class Session {
  /// Creates a session.
  Session({
    required this.id,
    Map<String, Object?>? data,
    DateTime? createdAt,
    DateTime? expiresAt,
  })  : data = data ?? <String, Object?>{},
        createdAt = createdAt ?? DateTime.now(),
        expiresAt = expiresAt ??
            (createdAt ?? DateTime.now()).add(const Duration(hours: 12));

  /// The identifier of the session.
  ///
  /// The identifier is random and is regenerated when the privileges of the
  /// session change, so a session id that leaked cannot be reused.
  final String id;

  /// What the service remembers about the session.
  final Map<String, Object?> data;

  /// When the session was created.
  final DateTime createdAt;

  /// When the session stops being valid.
  final DateTime expiresAt;

  /// Whether the session is past its expiry.
  bool isExpired([DateTime? now]) => (now ?? DateTime.now()).isAfter(expiresAt);

  /// A copy of the session with the given fields replaced.
  Session copyWith({
    String? id,
    Map<String, Object?>? data,
    DateTime? createdAt,
    DateTime? expiresAt,
  }) =>
      Session(
        id: id ?? this.id,
        data: data ?? this.data,
        createdAt: createdAt ?? this.createdAt,
        expiresAt: expiresAt ?? this.expiresAt,
      );
}

/// The store that keeps the sessions.
///
/// A service that runs in more than one process needs a store that is shared
/// between the processes — Redis or Postgres, for instance. The store of the
/// memory is meant for a service that runs in one process and for the tests.
abstract class SessionStore {
  /// Reads the session [id], or returns `null` when it is unknown.
  Future<Session?> find(String id);

  /// Writes the [session].
  Future<void> save(Session session);

  /// Removes the session [id].
  Future<void> delete(String id);
}

/// A store that keeps the sessions in the memory of the process.
class MemorySessionStore implements SessionStore {
  /// Creates a store.
  MemorySessionStore({this.maxSessions = 10000});

  /// How many sessions the store keeps at most.
  ///
  /// The oldest session is dropped when the store is full, so a service that
  /// never logs anybody out cannot grow without a bound.
  final int maxSessions;

  final Map<String, Session> _sessions = <String, Session>{};

  /// The sessions the store holds.
  int get length => _sessions.length;

  @override
  Future<Session?> find(String id) async => _sessions[id];

  @override
  Future<void> save(Session session) async {
    if (!_sessions.containsKey(session.id) && _sessions.length >= maxSessions) {
      final oldest = _sessions.keys.first;
      _sessions.remove(oldest);
    }
    _sessions[session.id] = session;
  }

  @override
  Future<void> delete(String id) async {
    _sessions.remove(id);
  }
}

/// The same site policy of the cookie of the session.
enum SessionCookieSameSite {
  /// The cookie is not sent with a cross site request.
  strict,

  /// The cookie is sent with a top level cross site request, e.g. a link.
  lax,

  /// The cookie is sent with every request.
  none,
}

/// Starts a session for a caller and saves it in the [store].
///
/// The session gets a fresh id, so an id that the caller knew before the
/// login cannot be used after it.
Future<Session> startSession(
  SessionStore store, {
  Map<String, Object?>? data,
  Duration lifetime = const Duration(hours: 12),
}) async {
  final now = DateTime.now();
  final session = Session(
    id: newSessionId(),
    data: data,
    createdAt: now,
    expiresAt: now.add(lifetime),
  );
  await store.save(session);
  return session;
}

/// Replaces the id of the [session] and saves it in the [store].
///
/// The id of a session is replaced when the privileges of the session change,
/// e.g. when the caller logs in. An id that leaked before the change is dead
/// afterwards, so the leak does not give the attacker the session.
Future<Session> regenerateSession(SessionStore store, Session session) async {
  final fresh = session.copyWith(
    id: newSessionId(),
    createdAt: DateTime.now(),
  );
  await store.delete(session.id);
  await store.save(fresh);
  return fresh;
}

/// Removes the [session] from the [store].
Future<void> destroySession(SessionStore store, Session session) =>
    store.delete(session.id);

/// The name of the cookie of the session.
const String sessionCookieName = 'laska_session';

/// Reads the value of the cookie [name] out of the header [header].
///
/// Returns `null` when the header holds no such cookie.
String? readCookie(String? header, String name) {
  if (header == null || header.isEmpty) {
    return null;
  }

  for (final part in header.split(';')) {
    final separator = part.indexOf('=');
    if (separator == -1) {
      continue;
    }
    if (part.substring(0, separator).trim() == name) {
      return Uri.decodeComponent(part.substring(separator + 1).trim());
    }
  }

  return null;
}

/// Renders the cookie of a session.
String renderSessionCookie(
  String id, {
  String name = sessionCookieName,
  DateTime? expires,
  bool secure = true,
  bool httpOnly = true,
  SessionCookieSameSite sameSite = SessionCookieSameSite.lax,
  String path = '/',
}) {
  final buffer = StringBuffer()
    ..write('$name=${Uri.encodeComponent(id)}')
    ..write('; Path=$path');

  if (httpOnly) {
    buffer.write('; HttpOnly');
  }
  if (secure) {
    buffer.write('; Secure');
  }

  switch (sameSite) {
    case SessionCookieSameSite.strict:
      buffer.write('; SameSite=Strict');
    case SessionCookieSameSite.lax:
      buffer.write('; SameSite=Lax');
    case SessionCookieSameSite.none:
      buffer.write('; SameSite=None');
  }

  if (expires != null) {
    buffer.write('; Expires=${_httpDate(expires)}');
  }

  return buffer.toString();
}

/// Renders the cookie that ends the session of the caller.
///
/// The browser drops the cookie when it reads this one, so the session of the
/// caller is over.
String renderClearedSessionCookie({
  String name = sessionCookieName,
  bool secure = true,
  bool httpOnly = true,
  SessionCookieSameSite sameSite = SessionCookieSameSite.lax,
  String path = '/',
}) {
  final buffer = StringBuffer()
    ..write('$name=')
    ..write('; Path=$path')
    ..write('; Max-Age=0')
    ..write('; Expires=${_httpDate(DateTime.utc(1970, 1, 1))}');

  if (httpOnly) {
    buffer.write('; HttpOnly');
  }
  if (secure) {
    buffer.write('; Secure');
  }

  switch (sameSite) {
    case SessionCookieSameSite.strict:
      buffer.write('; SameSite=Strict');
    case SessionCookieSameSite.lax:
      buffer.write('; SameSite=Lax');
    case SessionCookieSameSite.none:
      buffer.write('; SameSite=None');
  }

  return buffer.toString();
}

/// A random identifier of a session.
///
/// The identifier is long enough that it cannot be guessed, and it is drawn
/// from a cryptographic source.
String newSessionId([Random? random]) {
  final source = random ?? Random.secure();
  final bytes = List<int>.generate(32, (_) => source.nextInt(256));
  return _base64Url(bytes);
}

/// The base64url encoding of [bytes], without the padding.
String _base64Url(List<int> bytes) {
  const alphabet =
      'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_';
  final buffer = StringBuffer();

  for (var index = 0; index < bytes.length; index += 3) {
    final remaining = bytes.length - index;
    final b0 = bytes[index];
    final b1 = remaining > 1 ? bytes[index + 1] : 0;
    final b2 = remaining > 2 ? bytes[index + 2] : 0;

    buffer.write(alphabet[b0 >> 2]);
    buffer.write(alphabet[((b0 & 0x03) << 4) | (b1 >> 4)]);
    if (remaining > 1) {
      buffer.write(alphabet[((b1 & 0x0f) << 2) | (b2 >> 6)]);
    }
    if (remaining > 2) {
      buffer.write(alphabet[b2 & 0x3f]);
    }
  }

  return buffer.toString();
}

/// The date of a cookie, in the format of HTTP.
String _httpDate(DateTime date) {
  const weekdays = <String>[
    'Mon',
    'Tue',
    'Wed',
    'Thu',
    'Fri',
    'Sat',
    'Sun',
  ];
  const months = <String>[
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

  final utc = date.toUtc();
  final hour = utc.hour.toString().padLeft(2, '0');
  final minute = utc.minute.toString().padLeft(2, '0');
  final second = utc.second.toString().padLeft(2, '0');

  return '${weekdays[utc.weekday - 1]}, ${utc.day.toString().padLeft(2, '0')} '
      '${months[utc.month - 1]} ${utc.year} '
      '$hour:$minute:$second GMT';
}
