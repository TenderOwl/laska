import 'app.dart';
import 'context.dart';
import 'errors.dart';
import 'middleware.dart';
import 'request.dart';
import 'response.dart';
import 'router.dart';

/// Turns a [Request] into a [Response].
///
/// The dispatcher is the single place where routing, the middleware chain and
/// the error rendering meet. The HTTP server and the test harness both use it,
/// so a test exercises exactly what production does.
class Dispatcher {
  /// Creates a dispatcher for [app].
  Dispatcher(this.app);

  /// The application the requests are dispatched to.
  final Laska app;

  /// The chain of middleware of every route, built once and kept.
  ///
  /// The chain of a route only changes when the middleware of the application
  /// or of one of its groups changes, so it is built again only then.
  final Map<RouteInfo, List<Middleware>> _chains =
      <RouteInfo, List<Middleware>>{};

  /// The state of the middleware when the chain of a route was built.
  final Map<RouteInfo, int> _states = <RouteInfo, int>{};

  /// The number of times the chain of a route was built.
  ///
  /// The counter is a diagnostic of the hot path: the chain of a route is
  /// built once and kept, so the counter only goes up when the middleware of
  /// the service changed.
  int get chainBuilds => _chainBuilds;
  int _chainBuilds = 0;

  /// Handles [request] and returns the response.
  Future<Response> dispatch(Request request) async {
    try {
      final match = app.router.lookup(request.method, request.path);
      if (match == null) {
        final allowed = app.router.allowedMethods(request.path);
        if (allowed.isNotEmpty) {
          return Response.problem(
            405,
            'Method Not Allowed',
            'The ${request.method} method is not allowed for this resource.',
            headers: <String, String>{
              'allow': (allowed.toList()..sort()).join(', '),
            },
          );
        }
        return Response.problem(
          404,
          'Not Found',
          'No route matches ${request.method} ${request.path}.',
        );
      }

      final route = match.route;

      // The parameters and the pattern of the route are written into the
      // request, so the request is not copied for every call.
      request.params = match.params;
      request.routePattern = route.path;

      final context = Context(request, app);
      return await _runChain(
        _chainOf(route),
        0,
        request,
        context,
        route.handler,
      );
    } on HttpException catch (error) {
      return Response.problem(
        error.status,
        titleFor(error.status),
        error.message,
        code: error.code,
        details: error.details,
        headers: error.headers,
      );
    } on FormatException catch (error) {
      return Response.problem(
        400,
        'Bad Request',
        error.message,
        code: 'invalid_payload',
      );
    } catch (error) {
      return Response.problem(
        500,
        'Internal Server Error',
        error.toString(),
      );
    }
  }

  /// Runs the middleware of [app] and of its groups around [handler].
  ///
  /// The gRPC server uses it, so a call that comes over gRPC goes through the
  /// same middleware as a call that comes over HTTP.
  Future<Response> runMiddleware(
    Laska app,
    Request request,
    Handler handler,
  ) async {
    final context = Context(request, app);
    return await _runChain(_middlewareOf(app), 0, request, context, handler);
  }

  /// The chain of middleware of the [route], built once and kept.
  ///
  /// The chain is built again when the middleware of the application or of one
  /// of its groups changed since it was built.
  List<Middleware> _chainOf(RouteInfo route) {
    final state = _stateOf(route.app);
    final cached = _chains[route];
    if (cached != null && _states[route] == state) {
      return cached;
    }

    final chain = <Middleware>[
      ..._middlewareOf(route.app),
      ...route.middleware,
    ];
    _chainBuilds++;
    _chains[route] = chain;
    _states[route] = state;
    return chain;
  }

  /// The state of the middleware of [app] and of its groups.
  ///
  /// The state changes when a middleware is added, so a chain that was built
  /// before is not used any more.
  static int _stateOf(Laska? app) {
    var state = 0;
    var current = app;
    while (current != null) {
      state = state * 31 + current.middleware.length;
      current = current.parent;
    }
    return state;
  }

  Future<Response> _runChain(
    List<Middleware> middleware,
    int index,
    Request request,
    Context context,
    Handler handler,
  ) {
    if (index >= middleware.length) {
      return Future<Response>.sync(() => handler(context));
    }
    final current = middleware[index];
    return Future<Response>.sync(
      () => current(
        request,
        () => _runChain(middleware, index + 1, request, context, handler),
      ),
    );
  }

  /// The middleware of the application and of its groups, outermost first.
  List<Middleware> _middlewareOf(Laska? app) {
    final levels = <Laska>[];
    var current = app;
    while (current != null) {
      levels.insert(0, current);
      current = current.parent;
    }
    return <Middleware>[for (final level in levels) ...level.middleware];
  }
}

/// The title used in a problem document for [status].
String titleFor(int status) {
  switch (status) {
    case 400:
      return 'Bad Request';
    case 401:
      return 'Unauthorized';
    case 403:
      return 'Forbidden';
    case 404:
      return 'Not Found';
    case 405:
      return 'Method Not Allowed';
    case 409:
      return 'Conflict';
    case 422:
      return 'Unprocessable Entity';
    case 429:
      return 'Too Many Requests';
    default:
      return status >= 500 ? 'Internal Server Error' : 'Error';
  }
}
