/// The gRPC side of a service.
///
/// A contract speaks two transports: the REST projection of the contract and
/// the methods of the contract itself. The runtime serves the second one, so
/// a caller that speaks gRPC — a service written in another language, a tool
/// of the ecosystem — reaches the same implementation the REST projection
/// reaches.
library;

import 'dart:async';

import 'package:grpc/grpc.dart' as grpc;

import 'app.dart';
import 'errors.dart';
import 'grpc_reflection.dart';
import 'middleware.dart';
import 'request.dart';
import 'resilience/status.dart';
import 'response.dart';
import 'router.dart';
import 'transport.dart';

/// The handler of a method of a gRPC service.
///
/// The handler takes the bytes of the request message and answers with the
/// bytes of the response message, both in the wire format of the protocol
/// buffers.
typedef GrpcHandler = Future<List<int>> Function(List<int> request);

/// A service of a contract, served over gRPC.
class GrpcService {
  /// Creates a service.
  GrpcService({
    required this.name,
    required this.methods,
    this.middleware = const <Middleware>[],
    this.descriptor,
  });

  /// The full name of the service, e.g. `users.v1.UsersService`.
  ///
  /// The name is the one the caller puts in the path of the call, e.g.
  /// `/users.v1.UsersService/GetUser`.
  final String name;

  /// The handlers of the methods, by the name of the method.
  ///
  /// The name of a method is the name of the contract, e.g. `GetUser`.
  final Map<String, GrpcHandler> methods;

  /// The middleware that runs before the method is called.
  ///
  /// It is the middleware of the route of the method over HTTP, so a service
  /// is protected the same way on both transports.
  final List<Middleware> middleware;

  /// The descriptor of the contract of the service.
  ///
  /// The descriptor is the `FileDescriptorSet` of the protocol buffers: the
  /// bytes that describe the files of the contract. The service of the
  /// reflection of gRPC serves it, so a tool discovers the methods of the
  /// service without the files of the contract.
  ///
  /// The value is `null` when the service was written by hand and carries no
  /// contract: the service is served, but a tool cannot describe it.
  final List<int>? descriptor;

  Laska? _app;

  /// The application the service was registered on.
  ///
  /// The registry of the application fills it in, so the middleware of the
  /// application and of its groups runs before the method.
  Laska? get app => _app;

  /// Attaches the service to [app], unless it is attached already.
  void _attach(Laska app) {
    _app ??= app;
  }
}

/// The registry of the gRPC services of an application.
///
/// The generated code registers the services of a contract here, so the
/// application serves them over gRPC without any extra wiring.
class GrpcServiceRegistry {
  /// Creates a registry of the services of [owner].
  GrpcServiceRegistry(this.owner);

  /// The application the services are registered on.
  final Laska owner;

  final List<GrpcService> _services = <GrpcService>[];

  /// The services registered on the application.
  List<GrpcService> get services => List<GrpcService>.unmodifiable(_services);

  /// Registers [service] on the application.
  void add(GrpcService service) {
    service._attach(owner);
    _services.add(service);
  }
}

/// The gRPC server of an application.
///
/// The server serves the services registered on the application: the services
/// the generated code registered, so a service answers over gRPC the same
/// contract it answers over HTTP.
class GrpcServer {
  /// Creates a server for the services registered on [app].
  ///
  /// The [reflection] tells whether the server serves the service of the
  /// reflection of gRPC: it is on by default, so a tool of the ecosystem
  /// discovers the methods of the services of the server.
  GrpcServer(
    this.app, {
    this.address = '0.0.0.0',
    int port = 50051,
    this.credentials,
    this.reflection = true,
  }) : _port = port;

  /// The application whose services are served.
  final Laska app;

  /// The address the server binds to.
  final String address;

  /// The port the server binds to.
  final int _port;

  /// The credentials of the server, `null` for an insecure server.
  final grpc.ServerCredentials? credentials;

  /// Whether the server serves the service of the reflection of gRPC.
  ///
  /// The service of the reflection tells a tool — `grpcurl`, a client of
  /// another language — which methods a running server serves. A server that
  /// does not want to be described turns it off.
  final bool reflection;

  grpc.Server? _server;
  int _calls = 0;

  /// The port the server listens on.
  ///
  /// It is the port the server was told to bind to, or the port the system
  /// picked when the server was told to bind to `0`.
  int get port => _server?.port ?? _port;

  /// Whether the server is started.
  bool get isRunning => _server != null;

  /// The services the server serves.
  List<GrpcService> get services => _collect(app);

  /// Starts the server.
  ///
  /// The server binds to [address] and [port]. A port of `0` lets the system
  /// pick one, and the port it picked is readable in [port].
  Future<void> start() async {
    if (_server != null) {
      return;
    }
    final contractServices = services;
    final served = <grpc.Service>[
      for (final service in contractServices) _ServiceAdapter(service, this),
    ];

    if (reflection) {
      // The service of the reflection is served under both names of the
      // protocol: the tools of the ecosystem speak one of them.
      final index = GrpcReflectionIndex(contractServices);
      served.add(GrpcReflectionService(index));
      served.add(
        GrpcReflectionService(index, serviceName: reflectionServiceV1Alpha),
      );
    }

    final server = _LaskaGrpcServer(services: served);
    await server.serve(address: address, port: port, security: credentials);
    _server = server;
  }

  /// Stops the server.
  ///
  /// The server waits for the streams of the calls that finished to be closed
  /// before it closes the connections: the clients close them in the
  /// background, and `package:http2` asserts that a connection does not end
  /// with an open stream.
  Future<void> stop() async {
    final server = _server;
    if (server == null) {
      return;
    }
    _server = null;
    if (_calls > 0) {
      await Future<void>.delayed(grpcSettleDelay);
    }
    await server.shutdown();
  }

  /// Records that the server answered a call.
  void _recordCall() {
    _calls++;
  }

  /// The services of [app] and of the groups of [app].
  static List<GrpcService> _collect(Laska app) {
    final services = <GrpcService>[...app.grpc.services];
    for (final group in app.groups) {
      services.addAll(_collect(group));
    }
    return services;
  }
}

/// The server of the services of the contracts.
///
/// The server answers the calls of the services it does not know itself: the
/// protocol of gRPC answers such a call and keeps the stream of it open until
/// the client goes away, so the connection of the service could not be closed
/// cleanly.
class _LaskaGrpcServer extends grpc.Server {
  // The named constructor of the server is used, so the parameter cannot be
  // forwarded to the constructor of the parent.
  // ignore: use_super_parameters
  _LaskaGrpcServer({required List<grpc.Service> services})
      : super.create(services: services);

  final Map<String, grpc.Service> _unknown = <String, grpc.Service>{};

  @override
  grpc.Service? lookupService(String service) =>
      super.lookupService(service) ??
      _unknown.putIfAbsent(service, () => _UnknownService(service));
}

/// The service that answers the calls of a service the server does not know.
class _UnknownService extends grpc.Service {
  _UnknownService(this.name);

  /// The name of the service the caller asked for.
  final String name;

  @override
  String get $name => name;

  @override
  grpc.ServiceMethod? $lookupMethod(String method) => _method;

  late final grpc.ServiceMethod<List<int>, List<int>> _method =
      grpc.ServiceMethod<List<int>, List<int>>(
    'Unknown',
    (grpc.ServiceCall call, Future<List<int>> request) async {
      throw grpc.GrpcError.unimplemented(
        'The service "$name" is not implemented',
      );
    },
    false,
    false,
    (List<int> value) => value,
    (List<int> value) => value,
  );
}

/// The adapter of a service of a contract to the gRPC protocol.
class _ServiceAdapter extends grpc.Service {
  _ServiceAdapter(this.service, this.server) {
    for (final entry in service.methods.entries) {
      final method = grpc.ServiceMethod<List<int>, List<int>>(
        entry.key,
        (grpc.ServiceCall call, Future<List<int>> request) =>
            _handle(call, entry.key, request),
        false,
        false,
        (List<int> value) => value,
        (List<int> value) => value,
      );
      _methods[entry.key] = method;
      $addMethod(method);
    }
  }

  /// The service of the contract.
  final GrpcService service;

  /// The server the service belongs to.
  final GrpcServer server;

  final Map<String, grpc.ServiceMethod<List<int>, List<int>>> _methods =
      <String, grpc.ServiceMethod<List<int>, List<int>>>{};

  /// The method that answers the calls of the methods the service does not
  /// have.
  ///
  /// The protocol of gRPC answers such a call itself, and the stream of the
  /// call stays open until the client goes away: the server keeps it in its
  /// connection, and the connection cannot be closed cleanly. The server
  /// answers the call itself, so the stream is closed the way every other
  /// stream is.
  late final grpc.ServiceMethod<List<int>, List<int>> _unknown =
      grpc.ServiceMethod<List<int>, List<int>>(
    'Unknown',
    (grpc.ServiceCall call, Future<List<int>> request) async {
      throw grpc.GrpcError.unimplemented(
        'The method "${_methodOf(call)}" of the service "${service.name}" is '
        'not implemented',
      );
    },
    false,
    false,
    (List<int> value) => value,
    (List<int> value) => value,
  );

  @override
  String get $name => service.name;

  @override
  grpc.ServiceMethod? $lookupMethod(String name) => _methods[name] ?? _unknown;

  /// Answers a call of the method [method].
  ///
  /// The call goes through the middleware of the application first, so a
  /// service that is protected over HTTP is protected over gRPC too.
  Future<List<int>> _handle(
    grpc.ServiceCall call,
    String method,
    Future<List<int>> request,
  ) async {
    final handler = service.methods[method];
    if (handler == null) {
      throw grpc.GrpcError.unimplemented(
        'The method "$method" of the service "${service.name}" is not '
        'implemented',
      );
    }

    try {
      final bytes = await request;
      server._recordCall();
      final response = await _run(call, method, (ctx) async {
        final body = await handler(bytes);
        return Response.bytes(body, contentType: 'application/protobuf');
      });

      if (response.status >= 400) {
        throw grpc.GrpcError.custom(
          grpcStatusOf(response.status),
          _detailOf(response),
        );
      }
      return response.body;
    } on grpc.GrpcError {
      rethrow;
    } on HttpException catch (error) {
      throw grpc.GrpcError.custom(grpcStatusOf(error.status), error.message);
    } on FormatException catch (error) {
      throw grpc.GrpcError.custom(
        GrpcStatus.invalidArgument,
        error.message,
      );
    } catch (error) {
      // The errors of the framework keep their status, so a service degrades
      // the same way whatever transport the caller used.
      throw grpc.GrpcError.custom(grpcStatusOfError(error), error.toString());
    }
  }

  /// Runs the middleware of the application around the handler.
  Future<Response> _run(
    grpc.ServiceCall call,
    String method,
    Handler handler,
  ) {
    final app = service.app;
    if (app == null) {
      throw StateError(
        'The service "${service.name}" is not registered on an application.',
      );
    }
    return app.dispatcher.runMiddleware(
      app,
      _requestOf(call, method),
      handler,
    );
  }

  /// The name of the method the call asks for.
  String _methodOf(grpc.ServiceCall call) {
    final path = call.clientMetadata?[':path'] ?? '';
    final parts = path.split('/');
    return parts.last;
  }

  /// The request the middleware of the call sees.
  ///
  /// The metadata of the call becomes the headers of the request, so the
  /// middleware of the authentication reads the credentials of the caller the
  /// same way it reads them over HTTP.
  Request _requestOf(grpc.ServiceCall call, String method) {
    final headers = <String, String>{};
    final metadata = call.clientMetadata;
    if (metadata != null) {
      for (final entry in metadata.entries) {
        if (entry.key.startsWith(':')) {
          continue;
        }
        headers[entry.key.toLowerCase()] = entry.value;
      }
    }

    final path = '/${service.name}/$method';
    return Request(
      method: 'POST',
      path: path,
      uri: path,
      query: const <String, String>{},
      headers: headers,
    );
  }

  /// The detail of an answer that is not a success.
  String _detailOf(Response response) {
    final detail = response.jsonObject['detail'];
    if (detail is String && detail.isNotEmpty) {
      return detail;
    }
    return response.text;
  }
}

/// Starts a gRPC server for the services registered on [app].
///
/// The services are the ones the generated code registered on the
/// application, so a service speaks its contract over gRPC without any extra
/// wiring. The server serves the service of the reflection of gRPC too, so a
/// tool of the ecosystem discovers the methods of the services. The server is
/// not stopped when the process ends: the caller owns it and stops it with
/// [GrpcServer.stop].
Future<GrpcServer> serveGrpc(
  Laska app, {
  Object address = '0.0.0.0',
  int port = 50051,
  bool reflection = true,
}) async {
  final server = GrpcServer(
    app,
    address: address is String ? address : address.toString(),
    port: port,
    reflection: reflection,
  );
  await server.start();
  return server;
}
