import 'app.dart';
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
}
