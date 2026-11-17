import 'middleware.dart';
import 'router.dart';

/// The application object.
///
/// A `Laska` instance owns a [router] and the global middleware chain. Groups
/// are created with [group] and share the router of their parent.
class Laska {
  /// Creates an application.
  Laska({
    Router? router,
    String prefix = '',
    List<Middleware> middleware = const <Middleware>[],
  })  : router = router ?? Router(),
        _prefix = prefix,
        middleware = List<Middleware>.of(middleware);

  /// The router holding every registered route.
  final Router router;

  /// Middleware applied to routes registered through this instance.
  final List<Middleware> middleware;

  final String _prefix;

  /// Registers a global middleware.
  void use(Middleware middleware) {
    this.middleware.add(middleware);
  }

  /// Registers a `GET` route.
  void get(String path, Handler handler,
          {List<Middleware> middleware = const <Middleware>[]}) =>
      add('GET', path, handler, middleware: middleware);

  /// Registers a `POST` route.
  void post(String path, Handler handler,
          {List<Middleware> middleware = const <Middleware>[]}) =>
      add('POST', path, handler, middleware: middleware);

  /// Registers a `PUT` route.
  void put(String path, Handler handler,
          {List<Middleware> middleware = const <Middleware>[]}) =>
      add('PUT', path, handler, middleware: middleware);

  /// Registers a `PATCH` route.
  void patch(String path, Handler handler,
          {List<Middleware> middleware = const <Middleware>[]}) =>
      add('PATCH', path, handler, middleware: middleware);

  /// Registers a `DELETE` route.
  void delete(String path, Handler handler,
          {List<Middleware> middleware = const <Middleware>[]}) =>
      add('DELETE', path, handler, middleware: middleware);

  /// Registers a route answering to the common HTTP methods.
  void any(String path, Handler handler,
      {List<Middleware> middleware = const <Middleware>[]}) {
    for (final method in const <String>[
      'GET',
      'POST',
      'PUT',
      'PATCH',
      'DELETE'
    ]) {
      add(method, path, handler, middleware: middleware);
    }
  }

  /// Registers a route for an arbitrary [method].
  void add(
    String method,
    String path,
    Handler handler, {
    List<Middleware> middleware = const <Middleware>[],
  }) {
    router.add(
      method,
      _join(_prefix, path),
      handler,
      middleware: <Middleware>[...this.middleware, ...middleware],
    );
  }

  /// Registers routes under [prefix].
  ///
  /// The middleware of the group is applied to every route registered inside
  /// it, after the middleware of the parent group.
  void group(
    String prefix,
    void Function(Laska group) callback, {
    List<Middleware> middleware = const <Middleware>[],
  }) {
    final child = Laska(
      router: router,
      prefix: _join(_prefix, prefix),
      middleware: <Middleware>[...this.middleware, ...middleware],
    );
    callback(child);
  }

  static String _join(String prefix, String path) {
    if (prefix.isEmpty) {
      return path;
    }
    if (path.isEmpty || path == '/') {
      return prefix;
    }
    return '$prefix$path';
  }
}
