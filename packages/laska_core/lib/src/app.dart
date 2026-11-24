import 'cache.dart';
import 'db/database.dart';
import 'dispatcher.dart';
import 'grpc.dart';
import 'lifecycle.dart';
import 'logger.dart';
import 'middleware.dart';
import 'response.dart';
import 'router.dart';
import 'static_files.dart';

/// The application object.
///
/// A `Laska` instance owns a [router], the global middleware chain and the
/// named middleware aliases. Groups are created with [group] and share the
/// router of their parent.
class Laska {
  /// Creates an application.
  Laska({
    Router? router,
    String prefix = '',
    List<Middleware> middleware = const <Middleware>[],
    this.parent,
  })  : router = router ?? Router(),
        _prefix = prefix,
        middleware = List<Middleware>.of(middleware);

  /// The router holding every registered route.
  final Router router;

  /// The middleware applied before the middleware of the route.
  ///
  /// In the root application the middleware is global: it runs for every route
  /// of the application, no matter whether the route was registered before or
  /// after the middleware. In a group it runs for the routes of that group.
  final List<Middleware> middleware;

  /// The group this instance belongs to, if any.
  final Laska? parent;

  /// The groups created on this application.
  ///
  /// The gRPC server walks the groups, so a service registered on a group is
  /// served over gRPC as well.
  final List<Laska> groups = <Laska>[];

  /// The gRPC services registered on the application.
  ///
  /// The generated code registers the services of a contract here, so the
  /// application serves them over gRPC without any extra wiring.
  late final GrpcServiceRegistry grpc = GrpcServiceRegistry(this);

  /// Named middleware, referenced by routes as `middleware: ['auth']`.
  final Map<String, Middleware> aliases = <String, Middleware>{};

  /// The database of the service.
  ///
  /// The migration runner needs it, so a service registers its database here
  /// and `laska migrate:run` can find it.
  Database? database;

  /// The logger of the service.
  ///
  /// The observability stack replaces it with the logger of the service, and
  /// the handlers reach it through `ctx.logger`, which correlates the records
  /// with the request.
  Logger logger = Logger();

  /// The directory holding the migration files.
  String migrationsDirectory = 'migrations';

  /// The hooks of the lifecycle of the application.
  ///
  /// The server calls them: the hooks of the start phase run before the port
  /// is bound, the hooks of the ready phase run when the service answers and
  /// the hooks of the shutdown phase run after the requests in flight
  /// finished.
  final Lifecycle lifecycle = Lifecycle();

  Cache? _cache;

  /// The cache of the service.
  ///
  /// A group inherits the cache of its parent, so a service sets the cache
  /// once on the root application and every group of it uses the same cache.
  Cache get cache {
    final own = _cache;
    if (own != null) {
      return own;
    }
    final inherited = parent?.cache;
    if (inherited != null) {
      return inherited;
    }
    final created = Cache.memory();
    _cache = created;
    return created;
  }

  set cache(Cache value) {
    _cache = value;
  }

  final String _prefix;

  late final Dispatcher _dispatcher = Dispatcher(this);

  /// The dispatcher turning a [Request] into a [Response].
  Dispatcher get dispatcher => _dispatcher;

  /// Registers a middleware.
  ///
  /// In the root application the middleware is global: it runs before the
  /// middleware of every group and of every route. In a group it runs for the
  /// routes of that group.
  void use(Middleware middleware) {
    this.middleware.add(middleware);
  }

  /// Registers a named middleware, so routes can refer to it by name.
  void alias(String name, Middleware middleware) {
    aliases[name] = middleware;
  }

  /// Registers a hook that runs when the application starts.
  ///
  /// The hook runs before the server binds the port, so it is the place to
  /// acquire the resources of the service: the pool of the database, the
  /// client of another service, the cache that is warmed with the values the
  /// service needs. A hook that throws keeps the service from starting.
  void onStart(LifecycleHook hook) {
    lifecycle.add(LifecyclePhase.start, hook);
  }

  /// Registers a hook that runs when the application is ready.
  ///
  /// The hook runs when the port is bound and the gRPC server of the service
  /// is up, so it is the place to announce the readiness of the service — to
  /// the supervisor, to a health probe or to the log.
  void onReady(LifecycleHook hook) {
    lifecycle.add(LifecyclePhase.ready, hook);
  }

  /// Registers a hook that runs when the application stops.
  ///
  /// The hook runs after the requests in flight finished, so the resources it
  /// releases are still alive while the last answers are written.
  void onShutdown(LifecycleHook hook) {
    lifecycle.add(LifecyclePhase.shutdown, hook);
  }

  /// The application and its groups, in the order the hooks of the lifecycle
  /// run.
  ///
  /// The application comes first, then its groups in the order they were
  /// created, and the groups of a group come after it.
  Iterable<Laska> get lifecycleTree sync* {
    yield this;
    for (final group in groups) {
      yield* group.lifecycleTree;
    }
  }

  /// Registers a `GET` route.
  void get(
    String path,
    Handler handler, {
    List<Object> middleware = const <Object>[],
    String? name,
  }) =>
      add('GET', path, handler, middleware: middleware, name: name);

  /// Registers a `POST` route.
  void post(
    String path,
    Handler handler, {
    List<Object> middleware = const <Object>[],
    String? name,
  }) =>
      add('POST', path, handler, middleware: middleware, name: name);

  /// Registers a `PUT` route.
  void put(
    String path,
    Handler handler, {
    List<Object> middleware = const <Object>[],
    String? name,
  }) =>
      add('PUT', path, handler, middleware: middleware, name: name);

  /// Registers a `PATCH` route.
  void patch(
    String path,
    Handler handler, {
    List<Object> middleware = const <Object>[],
    String? name,
  }) =>
      add('PATCH', path, handler, middleware: middleware, name: name);

  /// Registers a `DELETE` route.
  void delete(
    String path,
    Handler handler, {
    List<Object> middleware = const <Object>[],
    String? name,
  }) =>
      add('DELETE', path, handler, middleware: middleware, name: name);

  /// Registers a route answering to the common HTTP methods.
  ///
  /// The name is registered for the first method only, because a name points
  /// at one route.
  void any(
    String path,
    Handler handler, {
    List<Object> middleware = const <Object>[],
    String? name,
  }) {
    var first = true;
    for (final method in const <String>[
      'GET',
      'POST',
      'PUT',
      'PATCH',
      'DELETE'
    ]) {
      add(method, path, handler,
          middleware: middleware, name: first ? name : null);
      first = false;
    }
  }

  /// Registers a route for an arbitrary [method].
  ///
  /// Middleware can be passed as [Middleware] instances or as the names of
  /// registered aliases. The middleware of the application and of the group
  /// runs before it.
  void add(
    String method,
    String path,
    Handler handler, {
    List<Object> middleware = const <Object>[],
    String? name,
  }) {
    router.add(
      method,
      _join(_prefix, path),
      handler,
      middleware: middleware.map(_resolveMiddleware).toList(),
      name: name,
      app: this,
    );
  }

  /// Registers routes under [prefix].
  ///
  /// The middleware of the group runs after the middleware of the application
  /// and before the middleware of the route.
  void group(
    String prefix,
    void Function(Laska group) callback, {
    List<Object> middleware = const <Object>[],
  }) {
    final child = Laska(
      router: router,
      prefix: _join(_prefix, prefix),
      parent: this,
      middleware: middleware.map(_resolveMiddleware).toList(),
    );
    groups.add(child);
    callback(child);
  }

  /// Serves the files of [directory] under [prefix].
  ///
  /// The prefix is the path the files are served from, e.g. `/assets` for the
  /// directory `web/assets`. A file is served with the content type of its
  /// extension, with the validators of the cache — an `ETag` and a
  /// `Last-Modified` — and with the header that keeps a browser from
  /// guessing the type of a file.
  ///
  /// The [fallback] file is served when the requested one is missing, e.g.
  /// `index.html` for a single page application. The [maxAge] is how long a
  /// browser may keep the file, and the [index] is the file served when the
  /// request points at a directory.
  ///
  /// The extra [headers] are written to every answer of the files.
  void staticFiles(
    String prefix,
    String directory, {
    String? fallback,
    Duration? maxAge,
    String index = 'index.html',
    Map<String, String> headers = const <String, String>{},
  }) {
    final files = StaticFiles(
      directory: directory,
      fallback: fallback,
      maxAge: maxAge,
      index: index,
      headers: headers,
    );
    final path = staticRoutePath(prefix);
    add('GET', path, (ctx) => files.handle(ctx.request));
    add('HEAD', path, (ctx) => files.handle(ctx.request));
  }

  /// Builds the path of the route registered under [name].
  String urlFor(String name, [Map<String, String> parameters = const {}]) =>
      router.urlFor(name, parameters);

  Middleware _resolveMiddleware(Object middleware) {
    if (middleware is Middleware) {
      return middleware;
    }
    if (middleware is String) {
      final resolved = _findAlias(middleware);
      if (resolved == null) {
        throw ArgumentError(
          'No middleware named "$middleware" is registered. '
          'Register it with app.alias("$middleware", middleware).',
        );
      }
      return resolved;
    }
    if (middleware is Function) {
      // A middleware written as an untyped closure is adapted here, so a
      // service may pass a plain `(request, next) async { ... }` literal.
      final function = middleware as dynamic;
      return (request, next) async {
        final result = await function(request, next);
        return result as Response;
      };
    }
    throw ArgumentError(
      'Middleware must be a Middleware or the name of an alias, '
      'got ${middleware.runtimeType}.',
    );
  }

  /// The middleware registered under [name], in this application or in one of
  /// its groups.
  Middleware? _findAlias(String name) {
    final resolved = aliases[name];
    if (resolved != null) {
      return resolved;
    }
    return parent?._findAlias(name);
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
