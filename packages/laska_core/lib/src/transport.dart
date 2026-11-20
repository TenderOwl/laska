/// The transports a service uses to talk to another service.
///
/// The runtime does not know whether the dependency answers over HTTP or over
/// gRPC: the generated client talks to a [ServiceTransport], and the transport
/// of the contract is chosen by the service that uses it.
library;

import 'dart:convert';

import 'package:grpc/grpc.dart' as grpc;
import 'package:http/http.dart' as http;

import 'resilience/errors.dart';
import 'resilience/status.dart';

/// A request to another service.
class TransportRequest {
  /// Creates a request.
  TransportRequest({
    required this.method,
    required this.uri,
    Map<String, String>? headers,
    this.body,
    this.contentType,
  }) : headers = <String, String>{...?headers};

  /// The HTTP method of the request, e.g. `GET`.
  final String method;

  /// Where the request goes.
  ///
  /// For a gRPC call the path of the URI is the path of the method, e.g.
  /// `/users.v1.UsersService/GetUser`.
  final Uri uri;

  /// The headers of the request.
  final Map<String, String> headers;

  /// The body of the request, `null` when it has none.
  final List<int>? body;

  /// The content type of the body.
  final String? contentType;

  /// The body decoded as UTF-8 text.
  String get text => utf8.decode(body ?? const <int>[], allowMalformed: true);

  /// Returns a copy of this request with the given fields replaced.
  TransportRequest copyWith({
    String? method,
    Uri? uri,
    Map<String, String>? headers,
    List<int>? body,
    String? contentType,
  }) =>
      TransportRequest(
        method: method ?? this.method,
        uri: uri ?? this.uri,
        headers: headers ?? this.headers,
        body: body ?? this.body,
        contentType: contentType ?? this.contentType,
      );
}

/// The answer of another service.
class TransportResponse {
  /// Creates a response.
  TransportResponse({
    required this.statusCode,
    Map<String, String>? headers,
    List<int>? body,
  })  : headers = <String, String>{...?headers},
        body = body ?? const <int>[];

  /// The status of the answer.
  final int statusCode;

  /// The headers of the answer.
  final Map<String, String> headers;

  /// The body of the answer.
  final List<int> body;

  /// The body decoded as UTF-8 text.
  String get text => utf8.decode(body, allowMalformed: true);

  /// Whether the answer is a success.
  bool get isSuccess => statusCode >= 200 && statusCode < 300;
}

/// The format of the body of a request.
enum BodyFormat {
  /// The body is a JSON document.
  json,

  /// The body is the binary format of the protocol buffers.
  protobuf,
}

/// Carries the requests of a client to another service.
abstract class ServiceTransport {
  /// The format of the bodies of the requests.
  BodyFormat get bodyFormat;

  /// Builds the address of a call.
  ///
  /// The [restPath] is the path of the REST projection of the contract, e.g.
  /// `/v1/users/u_1`, and the [rpcPath] is the path of the method of the
  /// contract, e.g. `/users.v1.UsersService/GetUser`. A transport that speaks
  /// HTTP uses the first one, a transport that speaks gRPC the second one.
  Uri buildUri(String restPath, String rpcPath);

  /// Sends [request] and waits for the answer.
  Future<TransportResponse> send(TransportRequest request);

  /// Releases the resources of the transport.
  Future<void> close();
}

/// A transport that talks to another service over HTTP.
class HttpServiceTransport implements ServiceTransport {
  /// Creates a transport talking to the service at [baseUrl].
  ///
  /// The [client] is closed with the transport when it was given by the
  /// caller.
  HttpServiceTransport({
    required this.baseUrl,
    http.Client? client,
  })  : _client = client ?? http.Client(),
        _ownsClient = client == null;

  /// The address of the service, e.g. `http://localhost:8080`.
  final String baseUrl;

  final http.Client _client;
  final bool _ownsClient;

  @override
  BodyFormat get bodyFormat => BodyFormat.json;

  @override
  Uri buildUri(String restPath, String rpcPath) =>
      Uri.parse('$baseUrl$restPath');

  @override
  Future<TransportResponse> send(TransportRequest request) async {
    final outgoing = http.Request(request.method, request.uri);
    request.headers.forEach((key, value) {
      outgoing.headers[key] = value;
    });
    final body = request.body;
    if (body != null) {
      outgoing.bodyBytes = body;
    }

    final streamed = await _client.send(outgoing);
    final response = await http.Response.fromStream(streamed);

    return TransportResponse(
      statusCode: response.statusCode,
      headers: response.headers,
      body: response.bodyBytes,
    );
  }

  @override
  Future<void> close() async {
    if (_ownsClient) {
      _client.close();
    }
  }
}

/// How long a gRPC connection waits for the streams of the calls that
/// finished to be closed.
///
/// The client of `package:grpc` closes the stream of a call in the
/// background, and `package:http2` asserts that a connection does not end
/// with an open stream: a connection that is closed too early takes the
/// assertion with it. The wait is the price of a shutdown that does not
/// crash the service.
const Duration grpcSettleDelay = Duration(milliseconds: 100);

/// A transport that talks to another service over gRPC.
///
/// The body of the request and the body of the answer are the bytes of the
/// messages of the contract, so the same contract speaks HTTP and gRPC.
class GrpcServiceTransport implements ServiceTransport {
  /// Creates a transport talking to [host] on [port].
  GrpcServiceTransport({
    required this.host,
    this.port = 50051,
    grpc.ClientChannel? channel,
    grpc.ChannelCredentials? credentials,
    Map<String, String>? metadata,
  })  : metadata = <String, String>{...?metadata},
        _channel = channel ??
            grpc.ClientChannel(
              host,
              port: port,
              options: grpc.ChannelOptions(
                credentials: credentials ?? grpc.ChannelCredentials.insecure(),
              ),
            );

  /// The host of the dependency.
  final String host;

  /// The port of the dependency.
  final int port;

  /// The metadata sent with every call.
  final Map<String, String> metadata;

  /// The headers that are not sent as the metadata of a gRPC call.
  ///
  /// The content type of a gRPC call is the one of the protocol, and the
  /// accept header of an HTTP call says nothing about a gRPC one.
  static const Set<String> _headersOfTheProtocol = <String>{
    'content-type',
    'accept',
  };

  final grpc.ClientChannel _channel;

  int _inFlight = 0;
  bool _called = false;

  @override
  BodyFormat get bodyFormat => BodyFormat.protobuf;

  @override
  Uri buildUri(String restPath, String rpcPath) =>
      Uri.parse('http://$host:$port$rpcPath');

  @override
  Future<TransportResponse> send(TransportRequest request) async {
    _inFlight++;
    _called = true;
    try {
      return await _send(request);
    } finally {
      _inFlight--;
    }
  }

  Future<TransportResponse> _send(TransportRequest request) async {
    final method = grpc.ClientMethod<List<int>, List<int>>(
      request.uri.path,
      (List<int> value) => value,
      (List<int> value) => value,
    );

    final call = _channel.createCall<List<int>, List<int>>(
      method,
      Stream<List<int>>.value(request.body ?? const <int>[]),
      grpc.CallOptions(metadata: _metadataOf(request)),
    );

    try {
      final body = await call.response.single;
      return TransportResponse(
        statusCode: 200,
        headers: await call.headers,
        body: body,
      );
    } on grpc.GrpcError catch (error) {
      throw DependencyFailure(
        '',
        statusCode: httpStatusOfGrpc(error.code),
        message: error.message ?? 'The gRPC call failed',
        cause: error,
      );
    }
  }

  /// The metadata of the call.
  ///
  /// The headers of the request are sent as the metadata of the call, so a
  /// caller that passes the token of a session reaches the service the same
  /// way it does over HTTP. The names of the metadata of gRPC are in lower
  /// case, so the names of the headers are lower-cased as well.
  ///
  /// The headers that belong to the protocol itself are left out: the content
  /// type of a gRPC call is the one of the protocol, and the accept header of
  /// an HTTP call says nothing about a gRPC one.
  Map<String, String> _metadataOf(TransportRequest request) {
    final result = <String, String>{...metadata};
    for (final entry in request.headers.entries) {
      final key = entry.key.toLowerCase();
      if (_headersOfTheProtocol.contains(key)) {
        continue;
      }
      result[key] = entry.value;
    }
    return result;
  }

  /// Closes the transport.
  ///
  /// The calls that are running are waited for — at most five seconds — and
  /// the channel is closed after the streams of the calls that finished are
  /// closed: the client of `package:grpc` closes them in the background, and
  /// `package:http2` asserts that a connection does not end with an open
  /// stream.
  @override
  Future<void> close() async {
    final deadline = DateTime.now().add(const Duration(seconds: 5));
    while (_inFlight > 0 && DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
    if (_called) {
      await Future<void>.delayed(grpcSettleDelay);
    }
    await _channel.shutdown();
  }
}

/// Reads the `retry-after` header of an answer.
///
/// The header holds either a number of seconds or a date. Returns `null` when
/// the header is missing or cannot be read.
Duration? parseRetryAfter(Map<String, String> headers) {
  String? value;
  for (final entry in headers.entries) {
    if (entry.key.toLowerCase() == 'retry-after') {
      value = entry.value;
      break;
    }
  }
  if (value == null) {
    return null;
  }

  final seconds = int.tryParse(value.trim());
  if (seconds != null) {
    return Duration(seconds: seconds);
  }

  final date = DateTime.tryParse(value.trim());
  if (date == null) {
    return null;
  }
  final left = date.difference(DateTime.now());
  return left.isNegative ? Duration.zero : left;
}
