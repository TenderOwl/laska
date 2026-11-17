import 'dart:async';

import 'request.dart';
import 'response.dart';

/// Continues the middleware chain.
typedef Next = Future<Response> Function();

/// A middleware around the request pipeline.
///
/// A middleware either calls [next] and returns its response, or short-circuits
/// the chain by returning a response of its own.
typedef Middleware = FutureOr<Response> Function(Request request, Next next);
