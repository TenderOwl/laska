import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'app.dart';
import 'context.dart';
import 'errors.dart';
import 'middleware.dart';
import 'request.dart';
import 'response.dart';
import 'router.dart';

/// Starts an HTTP server for [app] and returns it.
///
/// The server is not started listening for [address] until the returned future
/// completes; use [run] for the batteries-included variant.
Future<HttpServer> serve(
  Laska app, {
  Object address = '127.0.0.1',
  int port = 0,
  bool shared = false,
}) async {
  final server = await HttpServer.bind(address, port, shared: shared);
  unawaited(
    server.forEach((HttpRequest request) => _handle(app, request)),
  );
  return server;
}

/// Starts an HTTP server for [app] and prints its address.
Future<HttpServer> run(
  Laska app, {
  Object address = '0.0.0.0',
  int port = 3789,
}) async {
  final server = await serve(app, address: address, port: port);
  stdout.writeln(
    '=> Laska listening on http://${server.address.host}:${server.port}',
  );
  return server;
}

Future<void> _handle(Laska app, HttpRequest httpRequest) async {
  final response = await _dispatch(app, httpRequest);
  httpRequest.response.statusCode = response.status;
  response.headers.forEach((name, value) {
    httpRequest.response.headers.set(name, value);
  });
  if (response.body.isNotEmpty) {
    httpRequest.response.add(response.body);
  }
  await httpRequest.response.close();
}

Future<Response> _dispatch(Laska app, HttpRequest httpRequest) async {
  try {
    final request = await _readRequest(httpRequest);
    final match = app.router.lookup(request.method, request.path);
    if (match == null) {
      final allowed = app.router.allowedMethods(request.path);
      if (allowed.isNotEmpty) {
        return Response.problem(
          405,
          'Method Not Allowed',
          'The ${request.method} method is not allowed for this resource.',
          headers: <String, String>{
            'allow': (allowed.toList()..sort()).join(', ')
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
      match.route.middleware,
      0,
      request,
      context,
      match.route.handler,
    );
  } on HttpException catch (error) {
    return Response.problem(
      error.status,
      _titleFor(error.status),
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
    () => current(request,
        () => _runChain(middleware, index + 1, request, context, handler)),
  );
}

Future<Request> _readRequest(HttpRequest httpRequest) async {
  final body = await utf8.decoder.bind(httpRequest).join();
  final headers = <String, String>{};
  httpRequest.headers.forEach((name, values) {
    headers[name.toLowerCase()] = values.join(', ');
  });
  return Request(
    method: httpRequest.method.toUpperCase(),
    path: httpRequest.uri.path,
    uri: httpRequest.uri.toString(),
    query: httpRequest.uri.queryParameters,
    headers: headers,
    body: body,
  );
}

String _titleFor(int status) {
  switch (status) {
    case 400:
      return 'Bad Request';
    case 401:
      return 'Unauthorized';
    case 403:
      return 'Forbidden';
    case 404:
      return 'Not Found';
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
