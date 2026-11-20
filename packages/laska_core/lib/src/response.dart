import 'dart:convert';

/// An outgoing HTTP response.
class Response {
  /// Creates a response.
  Response({
    this.status = 200,
    Map<String, String>? headers,
    List<int>? body,
  })  : headers = <String, String>{...?headers},
        body = body ?? const <int>[];

  /// HTTP status code.
  final int status;

  /// Response headers.
  final Map<String, String> headers;

  /// Response body bytes.
  final List<int> body;

  /// The body decoded as UTF-8 text.
  String get text => utf8.decode(body, allowMalformed: true);

  /// The body decoded as JSON, or `null` when the body is empty.
  Object? get json {
    if (body.isEmpty) {
      return null;
    }
    try {
      return jsonDecode(text);
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

  /// Returns a copy of this response with the given fields replaced.
  Response copyWith({
    int? status,
    Map<String, String>? headers,
    List<int>? body,
  }) =>
      Response(
        status: status ?? this.status,
        headers: headers ?? this.headers,
        body: body ?? this.body,
      );

  /// Creates a JSON response.
  factory Response.json(
    Object? data, {
    int status = 200,
    Map<String, String>? headers,
  }) =>
      Response(
        status: status,
        headers: <String, String>{
          'content-type': 'application/json; charset=utf-8',
          ...?headers,
        },
        body: utf8.encode(jsonEncode(data)),
      );

  /// Creates a plain text response.
  factory Response.text(
    String data, {
    int status = 200,
    Map<String, String>? headers,
  }) =>
      Response(
        status: status,
        headers: <String, String>{
          'content-type': 'text/plain; charset=utf-8',
          ...?headers,
        },
        body: utf8.encode(data),
      );

  /// Creates an HTML response.
  factory Response.html(
    String data, {
    int status = 200,
    Map<String, String>? headers,
  }) =>
      Response(
        status: status,
        headers: <String, String>{
          'content-type': 'text/html; charset=utf-8',
          ...?headers,
        },
        body: utf8.encode(data),
      );

  /// Creates a response with raw bytes.
  factory Response.bytes(
    List<int> data, {
    int status = 200,
    String contentType = 'application/octet-stream',
    Map<String, String>? headers,
  }) =>
      Response(
        status: status,
        headers: <String, String>{'content-type': contentType, ...?headers},
        body: data,
      );

  /// Creates an RFC 9457 problem document.
  factory Response.problem(
    int status,
    String title,
    String detail, {
    String? code,
    Object? details,
    Map<String, String>? headers,
  }) {
    final document = <String, dynamic>{
      'type': 'about:blank',
      'title': title,
      'status': status,
      'detail': detail,
      if (code != null) 'code': code,
      if (details != null) 'errors': details,
    };
    return Response.json(
      document,
      status: status,
      headers: <String, String>{
        'content-type': 'application/problem+json; charset=utf-8',
        ...?headers,
      },
    );
  }
}
