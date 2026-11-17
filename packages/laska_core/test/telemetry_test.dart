import 'dart:convert';

import 'package:laska_core/laska_core.dart';
import 'package:test/test.dart';

/// A tracer that records the spans, so a test can assert what was traced.
class RecordingTracer implements Tracer {
  final List<RecordedSpan> spans = <RecordedSpan>[];

  RecordedSpan get lastSpan => spans.last;

  /// The spans called [name].
  List<RecordedSpan> spansNamed(String name) =>
      spans.where((span) => span.name == name).toList();

  @override
  Span startSpan(
    String name, {
    SpanContext? parent,
    Map<String, Object?> attributes = const <String, Object?>{},
    SpanKind kind = SpanKind.internal,
  }) {
    final span = RecordedSpan(
      name: name,
      kind: kind,
      parent: parent ?? currentSpan?.context,
      attributes: Map<String, Object?>.of(attributes),
    );
    spans.add(span);
    return span;
  }

  @override
  SpanContext? extract(Map<String, String> headers) =>
      SpanContext.parseTraceParent(headers['traceparent']);

  @override
  void inject(SpanContext context, Map<String, String> headers) {
    headers['traceparent'] = context.toTraceParent();
  }
}

/// A span recorded by a [RecordingTracer].
class RecordedSpan implements Span {
  RecordedSpan({
    required this.name,
    required this.kind,
    required this.parent,
    required this.attributes,
  });

  final String name;
  final SpanKind kind;
  final SpanContext? parent;
  final Map<String, Object?> attributes;
  final List<Object> errors = <Object>[];
  bool ended = false;

  int _counter = 0;

  @override
  SpanContext get context => SpanContext(
        traceId: parent?.traceId ?? 'a' * 32,
        spanId: 'b' * 15 + '${_counter++}',
      );

  @override
  void setAttribute(String name, Object? value) {
    attributes[name] = value;
  }

  @override
  void recordError(Object error, [StackTrace? stackTrace]) {
    errors.add(error);
  }

  @override
  void end() {
    ended = true;
  }
}

Request _request(
  String method,
  String path, {
  Map<String, String>? headers,
}) =>
    Request(
      method: method,
      path: Uri.parse(path).path,
      uri: path,
      query: const <String, String>{},
      headers: headers ?? const <String, String>{},
    );

void main() {
  group('SpanContext', () {
    test('writes the traceparent header', () {
      const context = SpanContext(
        traceId: '4bf92f3577b34da6a3ce929d0e0e4736',
        spanId: '00f067aa0ba902b7',
      );

      expect(
        context.toTraceParent(),
        '00-4bf92f3577b34da6a3ce929d0e0e4736-00f067aa0ba902b7-01',
      );
    });

    test('reads the traceparent header', () {
      final context = SpanContext.parseTraceParent(
        '00-4bf92f3577b34da6a3ce929d0e0e4736-00f067aa0ba902b7-01',
      );

      expect(context, isNotNull);
      expect(context!.traceId, '4bf92f3577b34da6a3ce929d0e0e4736');
      expect(context.spanId, '00f067aa0ba902b7');
      expect(context.sampled, isTrue);
    });

    test('rejects a malformed traceparent header', () {
      expect(SpanContext.parseTraceParent(null), isNull);
      expect(SpanContext.parseTraceParent(''), isNull);
      expect(SpanContext.parseTraceParent('nonsense'), isNull);
      expect(
        SpanContext.parseTraceParent(
          '00-4bf92f3577b34da6a3ce929d0e0e4736-00f067aa0ba902b7',
        ),
        isNull,
      );
      expect(
        SpanContext.parseTraceParent(
          '00-00000000000000000000000000000000-00f067aa0ba902b7-01',
        ),
        isNull,
      );
    });
  });

  group('tracingMiddleware', () {
    test('creates a server span for the request', () async {
      final tracer = RecordingTracer();
      final middleware = tracingMiddleware(tracer);

      await middleware(_request('GET', '/users'), () async {
        return Response.text('ok');
      });

      expect(tracer.spans, hasLength(1));
      final span = tracer.lastSpan;
      expect(span.name, 'http.server');
      expect(span.kind, SpanKind.server);
      expect(span.attributes['http.request.method'], 'GET');
      expect(span.attributes['url.path'], '/users');
      expect(span.ended, isTrue);
    });

    test('continues the trace of the caller', () async {
      final tracer = RecordingTracer();
      final middleware = tracingMiddleware(tracer);
      const incoming = SpanContext(
        traceId: '4bf92f3577b34da6a3ce929d0e0e4736',
        spanId: '00f067aa0ba902b7',
      );

      await middleware(
        _request(
          'GET',
          '/users',
          headers: <String, String>{'traceparent': incoming.toTraceParent()},
        ),
        () async => Response.text('ok'),
      );

      expect(tracer.lastSpan.parent?.traceId, incoming.traceId);
      expect(tracer.lastSpan.parent?.spanId, incoming.spanId);
    });

    test('sets the status of the response on the span', () async {
      final tracer = RecordingTracer();
      final middleware = tracingMiddleware(tracer);

      await middleware(
        _request('GET', '/users'),
        () async => Response.text('ok', status: 201),
      );

      expect(tracer.lastSpan.attributes['http.response.status_code'], 201);
    });

    test('records the error of a failing handler', () async {
      final tracer = RecordingTracer();
      final middleware = tracingMiddleware(tracer);

      await expectLater(
        middleware(_request('GET', '/users'), () async {
          throw StateError('boom');
        }),
        throwsStateError,
      );

      expect(tracer.lastSpan.errors, hasLength(1));
      expect(tracer.lastSpan.ended, isTrue);
    });

    test('makes the span the current span of the request', () async {
      final tracer = RecordingTracer();
      final middleware = tracingMiddleware(tracer);
      Span? inside;

      await middleware(_request('GET', '/users'), () async {
        inside = currentSpan;
        return Response.text('ok');
      });

      expect(inside, isNotNull);
      expect(inside!.context.traceId, tracer.lastSpan.context.traceId);
      expect(currentSpan, isNull);
    });

    test('puts the trace context on the request', () async {
      final tracer = RecordingTracer();
      final middleware = tracingMiddleware(tracer);
      final request = _request('GET', '/users');

      await middleware(request, () async => Response.text('ok'));

      expect(request.traceContext, isNotNull);
      expect(request.traceContext!.traceId, tracer.lastSpan.context.traceId);
    });
  });

  group('metricsMiddleware', () {
    test('counts the requests', () async {
      final registry = MetricsRegistry();
      final middleware = metricsMiddleware(registry);

      await middleware(_request('GET', '/users'), () async {
        return Response.text('ok');
      });

      final text = registry.toPrometheus();
      expect(text, contains('laska_http_requests_total'));
      expect(text, contains('method="GET"'));
      expect(text, contains('status="200"'));
    });

    test('records the duration of the request', () async {
      final registry = MetricsRegistry();
      final middleware = metricsMiddleware(registry);

      await middleware(_request('GET', '/users'), () async {
        return Response.text('ok');
      });

      final text = registry.toPrometheus();
      expect(text, contains('laska_http_request_duration_seconds_bucket'));
      expect(text, contains('laska_http_request_duration_seconds_count'));
    });

    test('counts a failing request', () async {
      final registry = MetricsRegistry();
      final middleware = metricsMiddleware(registry);

      await expectLater(
        middleware(_request('GET', '/users'), () async {
          throw StateError('boom');
        }),
        throwsStateError,
      );

      expect(registry.toPrometheus(), contains('status="error"'));
    });

    test('uses the route of the template as a label', () async {
      final registry = MetricsRegistry();
      final middleware = metricsMiddleware(registry);
      final request = _request('GET', '/users/42');
      request.routePattern = '/users/:id';

      await middleware(request, () async => Response.text('ok'));

      expect(registry.toPrometheus(), contains('route="/users/:id"'));
    });
  });

  group('MetricsRegistry', () {
    test('renders a counter', () {
      final registry = MetricsRegistry();
      registry
          .counter('laska_requests_total', description: 'The requests.')
          .add(3);

      expect(
        registry.toPrometheus(),
        '# HELP laska_requests_total The requests.\n'
        '# TYPE laska_requests_total counter\n'
        'laska_requests_total 3\n',
      );
    });

    test('keeps the series of the labels apart', () {
      final registry = MetricsRegistry();
      final counter = registry.counter('laska_requests_total')
        ..add(1, <String, String>{'method': 'GET'})
        ..add(2, <String, String>{'method': 'POST'});

      expect(counter, isNotNull);
      final text = registry.toPrometheus();
      expect(text, contains('laska_requests_total{method="GET"} 1'));
      expect(text, contains('laska_requests_total{method="POST"} 2'));
    });

    test('renders a histogram', () {
      final registry = MetricsRegistry();
      registry.histogram('laska_duration_seconds',
          buckets: <double>[0.1, 1]).record(0.05);

      final text = registry.toPrometheus();
      expect(text, contains('# TYPE laska_duration_seconds histogram'));
      expect(text, contains('laska_duration_seconds_bucket{le="0.1"} 1'));
      expect(text, contains('laska_duration_seconds_bucket{le="1"} 1'));
      expect(text, contains('laska_duration_seconds_bucket{le="+Inf"} 1'));
      expect(text, contains('laska_duration_seconds_count 1'));
      expect(text, contains('laska_duration_seconds_sum 0.05'));
    });

    test('counts the observations per bucket', () {
      final registry = MetricsRegistry();
      final histogram = registry.histogram(
        'laska_duration_seconds',
        buckets: <double>[0.1, 1],
      );
      histogram.record(0.05);
      histogram.record(0.5);

      final text = registry.toPrometheus();
      expect(text, contains('laska_duration_seconds_bucket{le="0.1"} 1'));
      expect(text, contains('laska_duration_seconds_bucket{le="1"} 2'));
      expect(text, contains('laska_duration_seconds_bucket{le="+Inf"} 2'));
      expect(text, contains('laska_duration_seconds_count 2'));
    });

    test('escapes the value of a label', () {
      final registry = MetricsRegistry();
      registry
          .counter('laska_requests_total')
          .add(1, <String, String>{'route': '/a "b"\\c'});

      expect(
        registry.toPrometheus(),
        contains(r'laska_requests_total{route="/a \"b\"\\c"} 1'),
      );
    });

    test('returns the same instrument for the same name', () {
      final registry = MetricsRegistry();
      final first = registry.counter('laska_requests_total');
      final second = registry.counter('laska_requests_total');

      first.add(1);
      second.add(1);

      expect(registry.toPrometheus(), contains('laska_requests_total 2'));
    });
  });

  group('TracingDatabase', () {
    test('creates a span for a query', () async {
      final tracer = RecordingTracer();
      final database = TracingDatabase(
        SqliteDatabase.memory(),
        tracer,
        system: 'sqlite',
      );

      await database.execute('CREATE TABLE users (id INTEGER PRIMARY KEY)');

      expect(tracer.spansNamed('db.execute'), hasLength(1));
      expect(tracer.spansNamed('db.execute').first.kind, SpanKind.client);
      expect(
        tracer.spansNamed('db.execute').first.attributes['db.system'],
        'sqlite',
      );
      await database.close();
    });

    test('records the error of a broken query', () async {
      final tracer = RecordingTracer();
      final database = TracingDatabase(SqliteDatabase.memory(), tracer);

      await expectLater(
        database.query('SELECT * FROM nowhere'),
        throwsA(isA<DatabaseException>()),
      );

      expect(tracer.spansNamed('db.query').first.errors, hasLength(1));
      await database.close();
    });
  });

  group('health probes', () {
    test('answers the liveness probe', () async {
      final app = Laska();
      registerHealthChecks(app);

      final response =
          await app.dispatcher.dispatch(_request('GET', '/healthz'));

      expect(response.status, 200);
      expect(response.jsonObject['status'], 'ok');
    });

    test('answers the readiness probe', () async {
      final app = Laska();
      registerHealthChecks(app);

      final response =
          await app.dispatcher.dispatch(_request('GET', '/readyz'));

      expect(response.status, 200);
      expect(response.jsonObject['status'], 'ok');
    });

    test('answers 503 when the service is not ready', () async {
      final app = Laska();
      registerHealthChecks(app, isReady: () async => false);

      final response =
          await app.dispatcher.dispatch(_request('GET', '/readyz'));

      expect(response.status, 503);
      expect(response.jsonObject['status'], 'unavailable');
    });

    test('the readiness follows the database', () async {
      final app = Laska();
      final database = SqliteDatabase.memory();
      app.database = database;
      registerHealthChecks(app, isReady: () => databaseReady(app.database));

      final response =
          await app.dispatcher.dispatch(_request('GET', '/readyz'));

      expect(response.status, 200);
      await database.close();
    });
  });

  group('Observability', () {
    test('installs the instrumentation of the service', () async {
      final app = Laska();
      final tracer = RecordingTracer();
      final registry = MetricsRegistry();

      await Observability.install(app, tracer: tracer, registry: registry);
      app.get('/users', (ctx) => ctx.text('ok'));

      final response = await app.dispatcher.dispatch(_request('GET', '/users'));

      expect(response.status, 200);
      expect(tracer.spans, hasLength(1));
      expect(registry.toPrometheus(), contains('laska_http_requests_total'));
    });

    test('serves the metrics', () async {
      final app = Laska();
      await Observability.install(app, registry: MetricsRegistry());
      app.get('/users', (ctx) => ctx.text('ok'));
      await app.dispatcher.dispatch(_request('GET', '/users'));

      final response =
          await app.dispatcher.dispatch(_request('GET', '/metrics'));

      expect(response.status, 200);
      expect(response.text, contains('laska_http_requests_total'));
    });

    test('correlates the logs with the request', () async {
      final lines = <String>[];
      final app = Laska();
      final tracer = RecordingTracer();
      await Observability.install(
        app,
        tracer: tracer,
        logger: Logger(sink: lines.add, service: 'users'),
      );
      app.get('/users', (ctx) {
        ctx.logger.info('handled');
        return ctx.text('ok');
      });

      await app.dispatcher.dispatch(_request('GET', '/users'));

      final records = lines
          .map((line) => jsonDecode(line) as Map<String, Object?>)
          .toList();
      final record = records.firstWhere(
        (entry) => entry['message'] == 'handled',
      );
      expect(record['request_id'], isA<String>());
      expect(record['trace_id'], isA<String>());
      expect(record['span_id'], isA<String>());
    });
  });
}
