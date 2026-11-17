/// A local OpenTelemetry collector for the development.
///
/// The collector accepts the OTLP over HTTP payloads of the services and
/// prints what it receives, so a developer sees the traces and the metrics of
/// the workspace without running a collector.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// A collector that prints the traces and the metrics it receives.
class LocalCollector {
  /// Creates a collector that writes to [sink].
  LocalCollector({void Function(String line)? sink})
      : _sink = sink ?? stdout.writeln;

  final void Function(String line) _sink;
  HttpServer? _server;

  /// The number of spans the collector received.
  int spansReceived = 0;

  /// The number of metric payloads the collector received.
  int metricsReceived = 0;

  /// The endpoint of the collector, once it is started.
  Uri get endpoint {
    final server = _server;
    if (server == null) {
      throw StateError('The collector is not started.');
    }
    return Uri.parse('http://127.0.0.1:${server.port}');
  }

  /// Starts the collector on [port].
  ///
  /// A port of `0` picks a free port, which is what the tests use.
  Future<void> start({String address = '127.0.0.1', int port = 4318}) async {
    final server = await HttpServer.bind(address, port);
    _server = server;
    unawaited(
      server.forEach((HttpRequest request) {
        unawaited(_handle(request));
      }),
    );
  }

  /// Stops the collector.
  Future<void> stop() async {
    final server = _server;
    _server = null;
    await server?.close(force: true);
  }

  Future<void> _handle(HttpRequest request) async {
    final body = await utf8.decoder.bind(request).join();

    // The payload is read before the answer is sent, so a client that waits
    // for the answer knows that the collector has seen the payload.
    if (body.isNotEmpty) {
      _read(body);
    }

    request.response.statusCode = 200;
    request.response.headers.contentType = ContentType.json;
    request.response.write('{}');
    await request.response.close();
  }

  void _read(String body) {
    try {
      final payload = jsonDecode(body);
      if (payload is! Map<String, dynamic>) {
        return;
      }
      if (payload.containsKey('resourceSpans')) {
        _handleTraces(payload);
      } else if (payload.containsKey('resourceMetrics')) {
        metricsReceived++;
        _sink('collector: received a metric payload');
      }
    } on FormatException {
      // A payload the collector cannot read is ignored, it never stops the
      // service that sent it.
    }
  }

  void _handleTraces(Map<String, dynamic> payload) {
    final resourceSpans = payload['resourceSpans'];
    if (resourceSpans is! List) {
      return;
    }

    for (final resource in resourceSpans) {
      if (resource is! Map<String, dynamic>) {
        continue;
      }
      final scopeSpans = resource['scopeSpans'];
      if (scopeSpans is! List) {
        continue;
      }
      for (final scope in scopeSpans) {
        if (scope is! Map<String, dynamic>) {
          continue;
        }
        final spans = scope['spans'];
        if (spans is! List) {
          continue;
        }
        for (final span in spans) {
          if (span is! Map<String, dynamic>) {
            continue;
          }
          spansReceived++;
          _sink(_describe(span));
        }
      }
    }
  }

  String _describe(Map<String, dynamic> span) {
    final name = span['name'] ?? 'span';
    final traceId = span['traceId'] ?? '';
    final spanId = span['spanId'] ?? '';
    final start = int.tryParse('${span['startTimeUnixNano'] ?? 0}') ?? 0;
    final end = int.tryParse('${span['endTimeUnixNano'] ?? 0}') ?? 0;
    final duration = start == 0 ? 0 : (end - start) / 1000000;
    return 'collector: trace ${_short(traceId)} span ${_short(spanId)} '
        '$name ${duration.toStringAsFixed(1)}ms';
  }

  static String _short(String id) {
    if (id.length <= 8) {
      return id;
    }
    return id.substring(0, 8);
  }
}
