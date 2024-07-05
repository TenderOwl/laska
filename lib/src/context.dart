import 'dart:convert' show jsonEncode;
import 'dart:io';

import 'package:laska/src/http/http_body.dart';

import 'package:laska/src/router.dart' show Route;

/// Context represents the context of the current HTTP request. It holds request and
/// response objects, path, path parameters, data and registered handler.
class Context {
  HttpRequest request;

  HttpResponse? response;

  Route? route;

  InternetAddress get realIp => request.connectionInfo!.remoteAddress;

  /// Scheme returns the HTTP protocol scheme, `http` or `https`.
  String get scheme => request.uri.scheme;

  /// Path returns the registered path for the handler.
  String get path => request.uri.path;

  /// Parse the request body and return `HttpBody` object.
  Future<HttpBody> get body async {
    return await HttpBodyHandler.processRequest(request);
  }

  /// List of all cookies in the request.
  List<Cookie> get cookies => request.cookies;

  /// Returns the query param for the provided [name].
  String? queryParam(String name) => request.uri.queryParameters[name];

  /// All the query parameters in request.
  Map<String, String>? get queryParams => request.uri.queryParameters;

  /// Returns the [Route] parameter for the provided [name].
  String? param(String name) => route?.params?[name];

  /// All the [Route] parameters in request.
  Map<String, String>? get params =>
      route?.params != null ? Map<String, String>.from(route!.params!) : null;

  /// Writes given string [s] as plain-text response.
  Future<void> text(String s, {int statusCode = 200}) async {
    await _writeResponse(s, statusCode: statusCode);
  }

  /// Writes given string [s] as HTML response.
  Future<void> html(String s, {int statusCode = 200}) async {
    await _writeResponse(s,
        contentType: ContentType.html, statusCode: statusCode);
  }

  /// Writes given [object] as JSON response.
  Future<void> json(dynamic object, {int statusCode = 200}) async {
    await _writeResponse(jsonEncode(object),
        contentType: ContentType.json, statusCode: statusCode);
  }

  /// Writes response to the response stream.
  ///
  /// If [contentType] is not provided, it will be set to `text/plain`.
  /// Sets [statusCode] to the response.
  Future<void> _writeResponse(String s,
      {ContentType? contentType, int statusCode = 200}) async {
    request.response.statusCode = statusCode;
    request.response.headers.contentType = contentType ?? ContentType.text;
    request.response.write(s);
  }

  Context(this.request, {this.route}) {
    response = request.response;
  }
}
