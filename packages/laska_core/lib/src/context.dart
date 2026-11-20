import 'app.dart';
import 'logger.dart';
import 'request.dart';
import 'response.dart';

/// Everything a handler needs: the request, the app and response builders.
class Context {
  /// Creates a context for [request] inside [app].
  Context(this.request, this.app);

  /// The incoming request.
  final Request request;

  /// The application the request is being handled by.
  final Laska app;

  /// The logger of the service, correlated with the request.
  ///
  /// Every record holds the id of the request and, when the request is traced,
  /// the id of the trace and of the span.
  Logger get logger => app.logger.child(<String, Object?>{
        if (request.id != null) 'request_id': request.id,
        if (request.traceContext != null)
          'trace_id': request.traceContext!.traceId,
        if (request.traceContext != null)
          'span_id': request.traceContext!.spanId,
      });

  /// Route parameters captured by the router.
  Map<String, String> get params => request.params;

  /// Query parameters.
  Map<String, String> get query => request.query;

  /// Request headers.
  Map<String, String> get headers => request.headers;

  /// HTTP method of the request.
  String get method => request.method;

  /// Path of the request.
  String get path => request.path;

  /// Builds a JSON response.
  Response json(Object? data, {int status = 200}) =>
      Response.json(data, status: status);

  /// Builds a plain text response.
  Response text(String data, {int status = 200}) =>
      Response.text(data, status: status);

  /// Builds an HTML response.
  ///
  /// The answer holds the content type of a document of HTML, so a browser
  /// reads it as a page and not as a text.
  Response html(String data, {int status = 200}) =>
      Response.html(data, status: status);
}
