import 'dart:convert';

import 'errors.dart';

/// An incoming HTTP request, decoupled from `dart:io`.
class Request {
  /// Creates a request.
  Request({
    required this.method,
    required this.path,
    required this.uri,
    required this.query,
    required this.headers,
    this.body = '',
    Map<String, String>? params,
  }) : params = params ?? const <String, String>{};

  /// HTTP method, upper case.
  final String method;

  /// Path part of the request URI, without the query string.
  final String path;

  /// Full request URI.
  final String uri;

  /// Decoded query parameters.
  final Map<String, String> query;

  /// Request headers with lower-cased names.
  final Map<String, String> headers;

  /// Raw request body.
  final String body;

  /// Route parameters captured by the router.
  final Map<String, String> params;

  /// Returns the value of the [name] header, or `null` when it is absent.
  String? header(String name) => headers[name.toLowerCase()];

  /// The `content-type` header, if present.
  String? get contentType => header('content-type');

  /// Whether the body is declared as JSON.
  bool get hasJsonBody => (contentType ?? '').contains('application/json');

  /// Decodes the body as a JSON object.
  ///
  /// Throws [HttpException] with status 400 when the body is not a JSON object.
  Map<String, dynamic> json() {
    if (body.trim().isEmpty) {
      return const <String, dynamic>{};
    }
    final Object? decoded;
    try {
      decoded = jsonDecode(body);
    } on FormatException {
      throw HttpException(400, 'Request body is not valid JSON');
    }
    if (decoded is! Map<String, dynamic>) {
      throw HttpException(400, 'Request body must be a JSON object');
    }
    return decoded;
  }

  /// Returns a copy of this request with the given [params].
  Request copyWith({Map<String, String>? params}) => Request(
        method: method,
        path: path,
        uri: uri,
        query: query,
        headers: headers,
        body: body,
        params: params ?? this.params,
      );
}
