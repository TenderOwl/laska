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

      final context = Context(request.copyWith(params: match.params), app);
      return await _runChain(
        <Middleware>[
          ..._middlewareOf(match.route.app),
          ...match.route.middleware,
        ],
        0,
        request,
        context,
        match.route.handler,
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
