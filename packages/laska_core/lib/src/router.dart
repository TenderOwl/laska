import 'dart:async';

import 'app.dart';
import 'context.dart';
import 'middleware.dart';
import 'response.dart';

/// A route handler.
typedef Handler = FutureOr<Response> Function(Context ctx);

/// A constraint on a route parameter.
///
/// Supported kinds: `int`, `float`, `bool`, `uuid`, `slug` and a custom
/// regular expression. A custom expression is written as `<pattern>` or as
/// `</pattern/>`; it always has to match the whole value.
class ParamConstraint {
  /// Creates a constraint of [kind] with an optional custom [pattern].
  const ParamConstraint(this.kind, [this.pattern]);

  /// The kind of the constraint.
  final String kind;

  /// The custom pattern, when the constraint was written as a regular
  /// expression.
  ///
  /// The expression is anchored, so it has to match the whole value.
  final RegExp? pattern;

  /// The kinds that are known by name.
  static const Set<String> kinds = <String>{
    'int',
    'float',
    'bool',
    'uuid',
    'slug',
  };

  /// Whether [value] satisfies the constraint.
  bool matches(String value) {
    final custom = pattern;
    if (custom != null) {
      return custom.hasMatch(value);
    }
    switch (kind) {
      case 'int':
        return RegExp(r'^-?\d+$').hasMatch(value);
      case 'float':
        return RegExp(r'^-?\d+(\.\d+)?$').hasMatch(value);
      case 'bool':
        return RegExp(r'^(true|false|0|1)$').hasMatch(value);
      case 'uuid':
        return RegExp(
          r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-'
          r'[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
        ).hasMatch(value);
      case 'slug':
        return RegExp(r'^[a-z0-9]+(?:-[a-z0-9]+)*$').hasMatch(value);
      default:
        return true;
    }
  }

  /// Parses the constraint written inside `<...>` in a route pattern.
  ///
  /// A constraint that is not a known kind is read as a regular expression.
  static ParamConstraint? parse(String raw) {
    if (raw.isEmpty) {
      return null;
    }
    if (raw.startsWith('/') && raw.endsWith('/') && raw.length > 1) {
      return ParamConstraint(
          'custom', _anchored(raw.substring(1, raw.length - 1)));
    }
    if (kinds.contains(raw)) {
      return ParamConstraint(raw);
    }
    return ParamConstraint('custom', _anchored(raw));
  }

  static RegExp _anchored(String source) => RegExp('^(?:$source)\$');
}

/// A segment of a route pattern.
class RouteSegment {
  /// Creates a segment.
  const RouteSegment({
    this.literal,
    this.parameter,
    this.constraint,
    this.optional = false,
    this.wildcard = false,
  });

  /// The literal text of the segment, when it is static.
  final String? literal;

  /// The name of the parameter, when the segment captures one.
  final String? parameter;

  /// The constraint of the parameter, if any.
  final ParamConstraint? constraint;

  /// Whether the parameter may be omitted.
  final bool optional;

  /// Whether the segment matches the rest of the path.
  final bool wildcard;

  /// The specificity of the segment: static beats constrained parameters,
  /// which beat plain parameters, which beat wildcards.
  int get specificity {
    if (literal != null) {
      return 3;
    }
    if (constraint != null) {
      return 2;
    }
    if (parameter != null) {
      return 1;
    }
    return 0;
  }

  @override
  String toString() {
    if (literal != null) {
      return literal!;
    }
    if (wildcard) {
      return '*';
    }
    final name = parameter!;
    final constraintText = constraint == null ? '' : '<${constraint!.kind}>';
    return ':$name$constraintText${optional ? '?' : ''}';
  }
}

/// A registered route.
class RouteInfo {
  /// Creates route metadata.
  RouteInfo({
    required this.method,
    required this.path,
    required this.segments,
    required this.handler,
    required this.middleware,
    this.name,
    this.app,
  });

  /// HTTP method, upper case.
  final String method;

  /// Normalised route pattern, e.g. `/v1/users/:id<int>`.
  final String path;

  /// The parsed segments of the pattern.
  final List<RouteSegment> segments;

  /// The handler of the route.
  final Handler handler;

  /// Middleware chain of the route, global middleware first.
  final List<Middleware> middleware;

  /// The name of the route, when it has one.
  final String? name;

  /// The application that registered the route.
  ///
  /// The dispatcher reads the middleware of the application and of its groups
  /// from it, so the global middleware applies to every route.
  final Laska? app;

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

/// Raised when a named route is unknown or cannot be generated.
class RouteNotFound implements Exception {
  /// Creates the exception.
  RouteNotFound(this.message);

  /// Human readable description of the problem.
  final String message;

  @override
  String toString() => 'RouteNotFound: $message';
}

/// A router with a static fast path and a segment matcher.
///
/// Supported pattern syntax:
///
/// * `/users` — a static segment;
/// * `/users/:id` — a named parameter;
/// * `/users/:id<int>` — a parameter with a constraint;
/// * `/users/:id?` — an optional trailing parameter;
/// * `/files/*` — a wildcard matching the rest of the path.
class Router {
  final List<RouteInfo> _routes = <RouteInfo>[];
  final Map<String, RouteInfo> _staticRoutes = <String, RouteInfo>{};
  final Map<String, RouteInfo> _namedRoutes = <String, RouteInfo>{};

  /// Registers a route.
  void add(
    String method,
    String path,
    Handler handler, {
    List<Middleware> middleware = const <Middleware>[],
    String? name,
    Laska? app,
  }) {
    final normalized = normalizePath(path);
    final route = RouteInfo(
      method: method.toUpperCase(),
      path: normalized,
      segments: parsePattern(normalized),
      handler: handler,
      middleware: List<Middleware>.of(middleware),
      name: name,
      app: app,
    );
    _routes.add(route);
    if (route.segments.every((segment) => segment.literal != null)) {
      _staticRoutes['${route.method} ${route.path}'] = route;
    }
    if (name != null) {
      final existing = _namedRoutes[name];
      if (existing != null) {
        throw ArgumentError(
          'A route named "$name" is already registered '
          '(${existing.method} ${existing.path}).',
        );
      }
      _namedRoutes[name] = route;
    }
  }

  /// Finds the route matching [method] and [path].
  ///
  /// When several routes match, the most specific one wins: static segments
  /// beat constrained parameters, which beat plain parameters, which beat
  /// wildcards.
  RouteMatch? lookup(String method, String path) {
    final normalized = normalizePath(path);
    final exact = _staticRoutes['${method.toUpperCase()} $normalized'];
    if (exact != null) {
      return RouteMatch(exact, const <String, String>{});
    }

    final segments = splitPath(normalized);
    RouteInfo? best;
    Map<String, String>? bestParams;
    var bestScore = -1;

    for (final route in _routes) {
      if (route.method != method.toUpperCase()) {
        continue;
      }
      final params = _match(route.segments, segments);
      if (params == null) {
        continue;
      }
      final score = _score(route.segments);
      if (score > bestScore) {
        best = route;
        bestParams = params;
        bestScore = score;
      }
    }

    if (best == null) {
      return null;
    }
    return RouteMatch(best, bestParams!);
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

  /// Renders the route table as an aligned text table.
  String table() {
    final rows = <List<String>>[
      for (final route in _routes)
        <String>[
          route.method,
          route.path,
          route.name ?? '',
          route.middleware.isEmpty ? '-' : '${route.middleware.length}',
        ],
    ];

    final headers = <String>['METHOD', 'PATH', 'NAME', 'MIDDLEWARE'];
    final widths = List<int>.generate(headers.length, (index) {
      var width = headers[index].length;
      for (final row in rows) {
        if (row[index].length > width) {
          width = row[index].length;
        }
      }
      return width;
    });

    final buffer = StringBuffer();
    void writeRow(List<String> row) {
      final cells = <String>[];
      for (var index = 0; index < row.length; index++) {
        cells.add(
          index == row.length - 1
              ? row[index].padRight(widths[index])
              : row[index].padRight(widths[index]),
        );
      }
      buffer.writeln(cells.join('  ').trimRight());
    }

    writeRow(headers);
    buffer.writeln(
      widths.map((width) => '-' * width).join('  '),
    );
    for (final row in rows) {
      writeRow(row);
    }
    return buffer.toString();
  }

  /// The route registered under [name], if any.
  RouteInfo? routeByName(String name) => _namedRoutes[name];

  /// Builds the path of the route registered under [name].
  ///
  /// Throws [RouteNotFound] when the route is unknown or when a parameter of
  /// the pattern is missing in [parameters].
  String urlFor(String name, [Map<String, String> parameters = const {}]) {
    final route = _namedRoutes[name];
    if (route == null) {
      throw RouteNotFound('No route named "$name" is registered.');
    }

    final buffer = StringBuffer();
    for (final segment in route.segments) {
      if (segment.literal != null) {
        buffer.write('/${segment.literal}');
        continue;
      }
      if (segment.wildcard) {
        final rest = parameters['*'] ?? '';
        buffer.write('/$rest');
        continue;
      }
      final value = parameters[segment.parameter];
      if (value == null) {
        if (segment.optional) {
          continue;
        }
        throw RouteNotFound(
          'The route "$name" needs a value for the parameter '
          '"${segment.parameter}".',
        );
      }
      buffer.write('/${Uri.encodeComponent(value)}');
    }
    return buffer.toString().isEmpty ? '/' : buffer.toString();
  }

  static int _score(List<RouteSegment> segments) {
    var score = 0;
    for (final segment in segments) {
      score = score * 10 + segment.specificity;
    }
    return score;
  }

  static Map<String, String>? _match(
    List<RouteSegment> pattern,
    List<String> path,
  ) {
    final params = <String, String>{};

    for (var i = 0; i < pattern.length; i++) {
      final segment = pattern[i];

      if (segment.wildcard) {
        if (i < path.length) {
          params['*'] = path.sublist(i).join('/');
        }
        return params;
      }

      if (i >= path.length) {
        if (segment.optional) {
          continue;
        }
        return null;
      }

      final value = path[i];
      final literal = segment.literal;
      if (literal != null) {
        if (literal != value) {
          return null;
        }
        continue;
      }

      final constraint = segment.constraint;
      if (constraint != null && !constraint.matches(value)) {
        return null;
      }
      params[segment.parameter!] = value;
    }

    if (path.length > pattern.length) {
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

/// Parses a route pattern into its segments.
List<RouteSegment> parsePattern(String pattern) {
  final segments = <RouteSegment>[];
  for (final raw in splitPattern(pattern)) {
    segments.add(_parseSegment(raw));
  }
  return segments;
}

/// Splits a route pattern into its segments.
///
/// A constraint written as `<...>` is kept in one piece, so a regular
/// expression may contain slashes.
List<String> splitPattern(String pattern) {
  final segments = <String>[];
  final buffer = StringBuffer();
  var depth = 0;

  for (var index = 0; index < pattern.length; index++) {
    final char = pattern[index];
    if (char == '<') {
      depth++;
    } else if (char == '>' && depth > 0) {
      depth--;
    } else if (char == '/' && depth == 0) {
      if (buffer.isNotEmpty) {
        segments.add(buffer.toString());
        buffer.clear();
      }
      continue;
    }
    buffer.write(char);
  }

  if (buffer.isNotEmpty) {
    segments.add(buffer.toString());
  }
  return segments;
}

RouteSegment _parseSegment(String raw) {
  if (raw == '*') {
    return const RouteSegment(wildcard: true);
  }
  if (!raw.startsWith(':')) {
    return RouteSegment(literal: raw);
  }

  var body = raw.substring(1);
  var optional = false;
  if (body.endsWith('?')) {
    optional = true;
    body = body.substring(0, body.length - 1);
  }

  ParamConstraint? constraint;
  final constraintStart = body.indexOf('<');
  if (constraintStart != -1) {
    final constraintEnd = body.lastIndexOf('>');
    if (constraintEnd > constraintStart) {
      constraint = ParamConstraint.parse(
        body.substring(constraintStart + 1, constraintEnd),
      );
      body = body.substring(0, constraintStart) +
          body.substring(constraintEnd + 1);
    }
  }

  return RouteSegment(
    parameter: body,
    constraint: constraint,
    optional: optional,
  );
}
