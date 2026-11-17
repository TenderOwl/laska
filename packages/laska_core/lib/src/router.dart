import 'dart:async';

import 'context.dart';
import 'middleware.dart';
import 'response.dart';

/// A route handler.
typedef Handler = FutureOr<Response> Function(Context ctx);

/// A registered route.
class RouteInfo {
  /// Creates route metadata.
  RouteInfo({
    required this.method,
    required this.path,
    required this.handler,
    required this.middleware,
  });

  /// HTTP method, upper case.
  final String method;

  /// Normalised route pattern, e.g. `/v1/users/:id`.
  final String path;

  /// The handler of the route.
  final Handler handler;

  /// Middleware chain of the route, global middleware first.
  final List<Middleware> middleware;

  /// The pattern split into segments.
  List<String> get segments => splitPath(path);

  @override
  String toString() => '$method $path';
}

/// A matched route with its captured parameters.
class RouteMatch {
  /// Creates a match.
  RouteMatch(this.route, this.params);

  /// The matched route.
  final RouteInfo route;

  /// Parameters captured from the request path.
  final Map<String, String> params;
}

/// A router with a static fast path and a segment matcher.
///
/// Supported pattern syntax:
/// * `/users` — a static segment;
/// * `/users/:id` — a named parameter;
/// * `/files/*` — a wildcard matching the rest of the path.
class Router {
  final List<RouteInfo> _routes = <RouteInfo>[];
  final Map<String, RouteInfo> _staticRoutes = <String, RouteInfo>{};

  /// Registers a route.
  void add(
    String method,
    String path,
    Handler handler, {
    List<Middleware> middleware = const <Middleware>[],
  }) {
    final route = RouteInfo(
      method: method.toUpperCase(),
      path: normalizePath(path),
      handler: handler,
      middleware: List<Middleware>.of(middleware),
    );
    _routes.add(route);
    if (!route.path.contains(':') && !route.path.contains('*')) {
      _staticRoutes['${route.method} ${route.path}'] = route;
    }
  }

  /// Finds the route matching [method] and [path].
  ///
  /// Returns `null` when no route matches; use [allowedMethods] to tell a 404
  /// from a 405.
  RouteMatch? lookup(String method, String path) {
    final normalized = normalizePath(path);
    final exact = _staticRoutes['${method.toUpperCase()} $normalized'];
    if (exact != null) {
      return RouteMatch(exact, const <String, String>{});
    }

    final segments = splitPath(normalized);
    for (final route in _routes) {
      if (route.method != method.toUpperCase()) {
        continue;
      }
      final params = _match(route.segments, segments);
      if (params != null) {
        return RouteMatch(route, params);
      }
    }
    return null;
  }

  /// Returns the methods allowed for [path].
  Set<String> allowedMethods(String path) {
    final segments = splitPath(normalizePath(path));
    final methods = <String>{};
    for (final route in _routes) {
      if (_match(route.segments, segments) != null) {
        methods.add(route.method);
      }
    }
    return methods;
  }

  /// All registered routes.
  List<RouteInfo> get routes => List<RouteInfo>.unmodifiable(_routes);

  static Map<String, String>? _match(List<String> pattern, List<String> path) {
    final params = <String, String>{};
    for (var i = 0; i < pattern.length; i++) {
      final segment = pattern[i];
      if (segment == '*') {
        return params;
      }
      if (i >= path.length) {
        return null;
      }
      if (segment.startsWith(':')) {
        params[segment.substring(1)] = path[i];
        continue;
      }
      if (segment != path[i]) {
        return null;
      }
    }
    if (path.length != pattern.length) {
      return null;
    }
    return params;
  }
}

/// Normalises [path]: adds a leading slash and removes a trailing one.
String normalizePath(String path) {
  var result = path;
  if (!result.startsWith('/')) {
    result = '/$result';
  }
  while (result.length > 1 && result.endsWith('/')) {
    result = result.substring(0, result.length - 1);
  }
  return result;
}

/// Splits [path] into non-empty segments.
List<String> splitPath(String path) => path
    .split('/')
    .where((segment) => segment.isNotEmpty)
    .toList(growable: false);
