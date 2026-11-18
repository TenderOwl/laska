import 'dart:convert';

import 'package:laska_core/laska_core.dart';

/// A transport that answers from a test instead of the network.
///
/// A generated client takes a transport, so a test can exercise the client
/// without opening a socket: the transport records the requests and answers
/// with the answers the test prepared. The retries, the circuit breaker and
/// the bulkhead of the client are therefore exercised for real.
class TestTransport implements ServiceTransport {
  /// Creates a transport.
  ///
  /// When a [handler] is given, it answers every request. Otherwise the
  /// transport answers with the answers and the failures the test prepared.
  TestTransport({
    this.bodyFormat = BodyFormat.json,
    Future<TransportResponse> Function(TransportRequest request)? handler,
  }) : _handler = handler;

  /// The format of the bodies of the requests.
  @override
  final BodyFormat bodyFormat;

  /// The requests the transport received, in order.
  final List<TransportRequest> requests = <TransportRequest>[];

  /// The number of requests the transport received.
  int get callCount => requests.length;

  final Future<TransportResponse> Function(TransportRequest request)? _handler;
  final List<TransportResponse> _answers = <TransportResponse>[];
  final List<Exception> _errors = <Exception>[];
  TransportResponse? _always;

  /// Prepares the answer of the next request.
  void enqueue(TransportResponse response) => _answers.add(response);

  /// Prepares the answer of the next request.
  ///
  /// The [body] is encoded as JSON when it is given.
  void enqueueResponse(
    int statusCode, {
    Object? body,
    Map<String, String>? headers,
  }) {
    enqueue(
      TransportResponse(
        statusCode: statusCode,
        headers: headers,
        body: body == null ? null : utf8.encode(jsonEncode(body)),
      ),
    );
  }

  /// Prepares the failure of the next request.
  void enqueueError(Exception error) => _errors.add(error);

  /// Makes the transport answer every request with [response].
  void alwaysRespond(TransportResponse response) => _always = response;

  @override
  Uri buildUri(String restPath, String rpcPath) =>
      Uri.parse('http://test.local$restPath');

  @override
  Future<TransportResponse> send(TransportRequest request) async {
    requests.add(request);

    final handler = _handler;
    if (handler != null) {
      return handler(request);
    }

    if (_errors.isNotEmpty) {
      throw _errors.removeAt(0);
    }

    if (_answers.isNotEmpty) {
      return _answers.removeAt(0);
    }

    final always = _always;
    if (always != null) {
      return always;
    }

    throw StateError(
      'The test transport has no answer for ${request.method} ${request.uri}.',
    );
  }

  @override
  Future<void> close() async {}
}
