import 'dart:convert';

import 'package:laska_core/laska_core.dart';

/// Raised when an expectation of a [TestResponse] is not met.
///
/// The name does not clash with the `TestFailure` of `package:test`, so a
/// test may import both packages.
class LaskaTestFailure implements Exception {
  /// Creates a failure with [message].
  LaskaTestFailure(this.message);

  /// Human readable description of the failure.
  final String message;

  @override
  String toString() => 'LaskaTestFailure: $message';
}

/// Creates a client that exercises [app] without opening a socket.
///
/// The client goes through the same dispatcher as the HTTP server, so a test
/// covers the routes, the middleware and the error rendering of the service.
TestClient testClient(Laska app) => TestClient(app);

/// A client that sends requests to an application in process.
class TestClient {
  /// Creates a client for [app].
  TestClient(this.app);

  /// The application the requests are sent to.
  final Laska app;

  /// Sends a `GET` request.
  Future<TestResponse> get(String path, {Map<String, String>? headers}) =>
      request('GET', path, headers: headers);

  /// Sends a `POST` request.
  Future<TestResponse> post(
    String path, {
    Object? body,
    Map<String, String>? headers,
  }) =>
      request('POST', path, body: body, headers: headers);

  /// Sends a `PUT` request.
  Future<TestResponse> put(
    String path, {
    Object? body,
    Map<String, String>? headers,
  }) =>
      request('PUT', path, body: body, headers: headers);

  /// Sends a `PATCH` request.
  Future<TestResponse> patch(
    String path, {
    Object? body,
    Map<String, String>? headers,
  }) =>
      request('PATCH', path, body: body, headers: headers);

  /// Sends a `DELETE` request.
  Future<TestResponse> delete(String path, {Map<String, String>? headers}) =>
      request('DELETE', path, headers: headers);

  /// Sends a request with [method] to [path].
  Future<TestResponse> request(
    String method,
    String path, {
    Object? body,
    Map<String, String>? headers,
  }) async {
    final uri = Uri.parse(path);
    final request = Request(
      method: method.toUpperCase(),
      path: uri.path,
      uri: path,
      query: uri.queryParameters,
      headers: <String, String>{
        ...?headers,
        if (body != null) 'content-type': 'application/json',
      },
      body: body == null ? '' : jsonEncode(body),
    );

    final response = await app.dispatcher.dispatch(request);
    return TestResponse(
      status: response.status,
      headers: response.headers,
      body: utf8.decode(response.body, allowMalformed: true),
    );
  }
}

/// The response of a [TestClient] request.
class TestResponse {
  /// Creates a response.
  TestResponse({
    required this.status,
    required this.headers,
    required this.body,
  });

  /// The status code of the response.
  final int status;

  /// The headers of the response.
  final Map<String, String> headers;

  /// The body of the response.
  final String body;

  /// The body decoded as JSON.
  Object? get json {
    if (body.isEmpty) {
      return null;
    }
    try {
      return jsonDecode(body);
    } on FormatException {
      return null;
    }
  }

  /// The body decoded as a JSON object.
  Map<String, dynamic> get jsonObject {
    final value = json;
    if (value is Map<String, dynamic>) {
      return value;
    }
    return const <String, dynamic>{};
  }

  /// Expects the status code to be [expected].
  TestResponse expectStatus(int expected) {
    if (status != expected) {
      throw LaskaTestFailure(
        'Expected status $expected but got $status. Body: $body',
      );
    }
    return this;
  }

  /// Expects the body to be [expected] once decoded as JSON.
  TestResponse expectJson(Object? expected) {
    final actual = json;
    if (!_deepEquals(actual, expected)) {
      throw LaskaTestFailure(
        'Expected JSON $expected but got $actual. Body: $body',
      );
    }
    return this;
  }

  /// Expects the header [name] to be [value].
  TestResponse expectHeader(String name, String value) {
    final actual = headers[name.toLowerCase()];
    if (actual != value) {
      throw LaskaTestFailure(
        'Expected header "$name" to be "$value" but got "$actual".',
      );
    }
    return this;
  }

  /// Expects the body to contain [text].
  TestResponse expectBodyContains(String text) {
    if (!body.contains(text)) {
      throw LaskaTestFailure(
          'Expected the body to contain "$text". Body: $body');
    }
    return this;
  }

  static bool _deepEquals(Object? a, Object? b) {
    if (identical(a, b)) {
      return true;
    }
    if (a is Map && b is Map) {
      if (a.length != b.length) {
        return false;
      }
      for (final key in a.keys) {
        if (!b.containsKey(key) || !_deepEquals(a[key], b[key])) {
          return false;
        }
      }
      return true;
    }
    if (a is List && b is List) {
      if (a.length != b.length) {
        return false;
      }
      for (var index = 0; index < a.length; index++) {
        if (!_deepEquals(a[index], b[index])) {
          return false;
        }
      }
      return true;
    }
    return a == b;
  }
}
