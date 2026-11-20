// GENERATED CODE - DO NOT MODIFY BY HAND.
//
// Source: shop_gateway.proto
// Regenerate with: laska contract compile

import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:laska_core/laska_core.dart';

// Messages

/// Request of the GetShopView method.
class GetShopViewRequest {
  /// Creates a GetShopViewRequest.
  const GetShopViewRequest({
    required this.id,
  });

  /// Stable identifier of the record.
  final String id;

  /// Builds a GetShopViewRequest from its JSON representation.
  factory GetShopViewRequest.fromJson(Map<String, dynamic> json) {
    final id = json['id'];
    if (id is! String) {
      throw const FormatException(
          'GetShopViewRequest.id must be of type String');
    }
    return GetShopViewRequest(
      id: id,
    );
  }

  /// The JSON representation of the GetShopViewRequest.
  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
      };

  /// The bytes of the message in the wire format of the protocol buffers.
  List<int> toProtoBytes() {
    final writer = ProtoWriter();
    if (id != '') {
      writer.writeString(1, id);
    }
    return writer.toBytes();
  }

  /// Reads a message out of the wire format of the protocol buffers.
  factory GetShopViewRequest.fromProtoBytes(List<int> bytes) {
    final reader = ProtoReader(bytes);
    var id = '';

    while (reader.hasNext) {
      final tag = reader.readTag();
      switch (tag) {
        case 1:
          id = reader.readString();
        default:
          reader.skipField();
      }
    }

    return GetShopViewRequest(
      id: id,
    );
  }
}

/// A record of the application.
class ShopView {
  /// Creates a ShopView.
  const ShopView({
    required this.id,
    required this.name,
  });

  /// Stable identifier of the record.
  final String id;

  /// Name of the record.
  final String name;

  /// Builds a ShopView from its JSON representation.
  factory ShopView.fromJson(Map<String, dynamic> json) {
    final id = json['id'];
    if (id is! String) {
      throw const FormatException('ShopView.id must be of type String');
    }
    final name = json['name'];
    if (name is! String) {
      throw const FormatException('ShopView.name must be of type String');
    }
    return ShopView(
      id: id,
      name: name,
    );
  }

  /// The JSON representation of the ShopView.
  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'name': name,
      };

  /// The bytes of the message in the wire format of the protocol buffers.
  List<int> toProtoBytes() {
    final writer = ProtoWriter();
    if (id != '') {
      writer.writeString(1, id);
    }
    if (name != '') {
      writer.writeString(2, name);
    }
    return writer.toBytes();
  }

  /// Reads a message out of the wire format of the protocol buffers.
  factory ShopView.fromProtoBytes(List<int> bytes) {
    final reader = ProtoReader(bytes);
    var id = '';
    var name = '';

    while (reader.hasNext) {
      final tag = reader.readTag();
      switch (tag) {
        case 1:
          id = reader.readString();
        case 2:
          name = reader.readString();
        default:
          reader.skipField();
      }
    }

    return ShopView(
      id: id,
      name: name,
    );
  }
}

// Service ShopGatewayService

/// ShopGatewayService manages the records of the application.
abstract class ShopGatewayService {
  /// GetShopView returns a single record by its identifier.
  Future<ShopView> getShopView(GetShopViewRequest request);
}

/// Registers the projections of [service] on [app].
///
/// The service is registered over HTTP and over gRPC, so the
/// contract of the service is served on both transports.
void registerShopGatewayService(
  Laska app,
  ShopGatewayService service, {
  List<Middleware> middleware = const <Middleware>[],
  bool grpc = true,
}) {
  app.get(
    '/v1/shop_gateway/:id',
    (ctx) async {
      final payload = <String, dynamic>{};
      payload['id'] = ctx.params['id']!;
      final request = GetShopViewRequest.fromJson(payload);
      final response = await service.getShopView(request);
      return ctx.json(response.toJson());
    },
    middleware: middleware,
  );

  if (grpc) {
    app.grpc.add(
      GrpcService(
        name: 'shop_gateway.v1.ShopGatewayService',
        methods: <String, GrpcHandler>{
          'GetShopView': (bytes) async {
            final request = GetShopViewRequest.fromProtoBytes(bytes);
            final response = await service.getShopView(request);
            return response.toProtoBytes();
          },
        },
        middleware: middleware,
      ),
    );
  }
}

/// The policies of the methods of the `ShopGatewayService` service.
///
/// The policies come from the `laska.policy` annotations of the
/// contract, so the way a method is called is visible in the
/// contract itself and not only in the code of the caller.
class ShopGatewayServicePolicies {
  const ShopGatewayServicePolicies._();

  /// The policy of the `GetShopView` method.
  static final DependencyPolicy getShopView = DependencyPolicy(
      timeout: Duration(seconds: 2),
      retry: RetryPolicy(
          maxAttempts: 3,
          initialBackoff: Duration(milliseconds: 100),
          maxBackoff: Duration(seconds: 2),
          jitter: true),
      idempotent: true);

  /// The policies of the methods, by the name of the method.
  static final Map<String, DependencyPolicy> policies =
      <String, DependencyPolicy>{
    'GetShopView': getShopView,
  };
}

/// Typed client for the `ShopGatewayService` service.
class ShopGatewayServiceClient {
  /// Creates a client talking to [baseUrl].
  ShopGatewayServiceClient({
    required this.baseUrl,
    ServiceTransport? transport,
    http.Client? httpClient,
    Duration timeout = const Duration(seconds: 2),
    Tracer? tracer,
    String dependencyName = 'ShopGatewayService',
    DependencyPolicy policy = const DependencyPolicy(),
    Map<String, DependencyPolicy>? policies,
  })  : _transport = transport ??
            HttpServiceTransport(baseUrl: baseUrl, client: httpClient),
        // ignore: prefer_initializing_formals
        _timeout = timeout,
        // ignore: prefer_initializing_formals
        _tracer = tracer,
        // ignore: prefer_initializing_formals
        _dependencyName = dependencyName,
        // ignore: prefer_initializing_formals
        _policy = policy,
        // ignore: prefer_initializing_formals
        _policies = <String, DependencyPolicy>{
          ...ShopGatewayServicePolicies.policies,
          ...?policies,
        };

  /// Base URL of the service, e.g. `http://localhost:8080`.
  final String baseUrl;

  /// The transport the calls go through.
  final ServiceTransport _transport;

  /// The timeout of the calls that have no policy of their own.
  final Duration _timeout;

  /// The tracer of the client, when the calls are traced.
  final Tracer? _tracer;

  /// The name of the dependency the calls go to.
  final String _dependencyName;

  /// The policy of the dependency.
  ///
  /// It holds the circuit breaker and the bulkhead of the
  /// dependency, which every call of the client shares.
  final DependencyPolicy _policy;

  /// The policy of every method, by the name of the method.
  final Map<String, DependencyPolicy> _policies;

  /// The dependency the calls go through.
  ///
  /// The dependency holds the circuit breaker and the bulkhead
  /// of the service, so every call of the client shares them.
  late final Dependency _dependency = Dependency(
    name: _dependencyName,
    transport: _transport,
    policy: _policy,
    tracer: _tracer,
  );

  /// GetShopView returns a single record by its identifier.
  ///
  /// The [headers] are sent with the call, e.g. the token of the caller.
  ///
  /// The client writes the `accept` and the `content-type` itself.
  Future<ShopView> getShopView(GetShopViewRequest request,
      {String? idempotencyKey, Map<String, String>? headers}) async {
    final uri = _transport.buildUri(
      '/v1/shop_gateway/${Uri.encodeComponent(request.id.toString())}',
      '/shop_gateway.v1.ShopGatewayService/GetShopView',
    );

    final requestHeaders = <String, String>{
      ...?headers,
      'accept': _transport.bodyFormat == BodyFormat.protobuf
          ? 'application/protobuf'
          : 'application/json',
    };

    if (idempotencyKey != null) {
      requestHeaders['idempotency-key'] = idempotencyKey;
    }

    final body = _transport.bodyFormat == BodyFormat.protobuf
        ? request.toProtoBytes()
        : null;

    final response = await _send(
      'GetShopView',
      'ShopGatewayService.GetShopView',
      'get',
      uri,
      requestHeaders,
      body,
    );

    return _transport.bodyFormat == BodyFormat.protobuf
        ? ShopView.fromProtoBytes(response.body)
        : ShopView.fromJson(jsonDecode(response.text) as Map<String, dynamic>);
  }

  /// Sends the request of a method of the service.
  ///
  /// The policy of the method decides how the call is timed out,
  /// how often it is retried and whether it may be retried at all.
  Future<TransportResponse> _send(
    String method,
    String operation,
    String verb,
    Uri uri,
    Map<String, String> headers,
    List<int>? body,
  ) async {
    final methodPolicy = _policies[method];
    final effectivePolicy = methodPolicy == null
        ? DependencyPolicy(timeout: _timeout)
        : methodPolicy.copyWith(
            timeout: methodPolicy.timeout ?? _timeout,
          );
    try {
      return await _dependency.call(
        TransportRequest(
          method: verb,
          uri: uri,
          headers: headers,
          body: body,
          contentType: body == null
              ? null
              : _transport.bodyFormat == BodyFormat.protobuf
                  ? "application/protobuf"
                  : "application/json",
        ),
        policy: effectivePolicy,
        operation: operation,
        attributes: <String, Object?>{
          'http.request.method': verb,
          'url.path': uri.path,
        },
      );
    } on DependencyFailure catch (error) {
      throw LaskaApiException(error.statusCode ?? 502, error.body);
    } on DependencyTimeoutException catch (error) {
      throw LaskaApiException(504, error.toString());
    } on CircuitOpenException catch (error) {
      throw LaskaApiException(503, error.toString());
    } on BulkheadFullException catch (error) {
      throw LaskaApiException(503, error.toString());
    }
  }
}
