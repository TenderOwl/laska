import 'package:grpc/grpc.dart' as grpc;
import 'package:laska_core/laska_core.dart';
import 'package:test/test.dart';

/// The descriptor of a contract with one service.
///
/// The descriptor is the `FileDescriptorSet` of the protocol buffers: the bytes
/// that describe the files of a contract.
List<int> _descriptor() {
  final id = ProtoWriter()
    ..writeString(1, 'id')
    ..writeInt32(3, 1)
    ..writeEnum(4, 1)
    ..writeEnum(5, 9)
    ..writeString(10, 'id');

  final user = ProtoWriter()
    ..writeString(1, 'User')
    ..writeMessage(2, id.toBytes());

  final request = ProtoWriter()
    ..writeString(1, 'GetUserRequest')
    ..writeMessage(2, id.toBytes());

  final method = ProtoWriter()
    ..writeString(1, 'GetUser')
    ..writeString(2, '.users.v1.GetUserRequest')
    ..writeString(3, '.users.v1.User');

  final service = ProtoWriter()
    ..writeString(1, 'UsersService')
    ..writeMessage(2, method.toBytes());

  final file = ProtoWriter()
    ..writeString(1, 'users.proto')
    ..writeString(2, 'users.v1')
    ..writeMessage(4, request.toBytes())
    ..writeMessage(4, user.toBytes())
    ..writeMessage(6, service.toBytes())
    ..writeString(12, 'proto3');

  return (ProtoWriter()..writeMessage(1, file.toBytes())).toBytes();
}

/// The bytes of the field [field] of the message [bytes].
List<List<int>> _bytesOf(List<int> bytes, int field) {
  final reader = ProtoReader(bytes);
  final values = <List<int>>[];

  while (reader.hasNext) {
    final tag = reader.readTag();
    if (tag == field) {
      values.add(reader.readBytes());
    } else {
      reader.skipField();
    }
  }

  return values;
}

/// The number of the field [field] of the message [bytes].
int _numberOf(List<int> bytes, int field) {
  final reader = ProtoReader(bytes);
  var value = 0;

  while (reader.hasNext) {
    final tag = reader.readTag();
    if (tag == field) {
      value = reader.readVarint();
    } else {
      reader.skipField();
    }
  }

  return value;
}

/// The string of the field [field] of the message [bytes].
String _stringOf(List<int> bytes, int field) {
  final reader = ProtoReader(bytes);
  var value = '';

  while (reader.hasNext) {
    final tag = reader.readTag();
    if (tag == field) {
      value = reader.readString();
    } else {
      reader.skipField();
    }
  }

  return value;
}

/// Asks the service of the reflection of the [server] the question [request].
///
/// The [service] is the name of the service of the reflection, the version 1
/// or the version 1alpha.
Future<List<int>> _ask(
  GrpcServer server,
  List<int> request, {
  String service = reflectionServiceV1,
}) async {
  final channel = grpc.ClientChannel(
    '127.0.0.1',
    port: server.port,
    options: const grpc.ChannelOptions(
      credentials: grpc.ChannelCredentials.insecure(),
    ),
  );
  addTearDown(channel.shutdown);

  final call = channel.createCall<List<int>, List<int>>(
    grpc.ClientMethod<List<int>, List<int>>(
      '/$service/$reflectionMethod',
      (List<int> value) => value,
      (List<int> value) => value,
    ),
    Stream<List<int>>.value(request),
    grpc.CallOptions(),
  );

  return call.response.single;
}

/// The request that asks for the list of the services.
List<int> _listServices() => (ProtoWriter()..writeString(7, '')).toBytes();

/// The request that asks for the file that declares the symbol [symbol].
List<int> _fileOfSymbol(String symbol) =>
    (ProtoWriter()..writeString(4, symbol)).toBytes();

void main() {
  group('the reflection of the gRPC server', () {
    late Laska app;
    late GrpcServer server;

    setUp(() async {
      app = Laska();
      app.grpc.add(
        GrpcService(
          name: 'users.v1.UsersService',
          methods: <String, GrpcHandler>{
            'GetUser': (bytes) async => bytes,
          },
          descriptor: _descriptor(),
        ),
      );
      server = await serveGrpc(app, address: '127.0.0.1', port: 0);
    });

    tearDown(() async {
      await server.stop();
    });

    test('lists the services of the server', () async {
      final answer = await _ask(server, _listServices());

      final list = _bytesOf(answer, 6);
      expect(list, hasLength(1));

      final services = _bytesOf(list.single, 1);
      expect(services, hasLength(1));
      expect(_stringOf(services.single, 1), 'users.v1.UsersService');
    });

    test('answers under the name of the version 1alpha too', () async {
      final answer = await _ask(
        server,
        _listServices(),
        service: reflectionServiceV1Alpha,
      );

      final list = _bytesOf(answer, 6);
      final services = _bytesOf(list.single, 1);
      expect(_stringOf(services.single, 1), 'users.v1.UsersService');
    });

    test('holds the file of a service', () async {
      final answer = await _ask(server, _fileOfSymbol('users.v1.UsersService'));

      final response = _bytesOf(answer, 4);
      expect(response, hasLength(1));

      final files = _bytesOf(response.single, 1);
      expect(files, hasLength(1));
      expect(_stringOf(files.single, 1), 'users.proto');
      expect(_stringOf(files.single, 2), 'users.v1');
    });

    test('holds the file of a method of a service', () async {
      final answer = await _ask(
        server,
        _fileOfSymbol('users.v1.UsersService.GetUser'),
      );

      final response = _bytesOf(answer, 4);
      final files = _bytesOf(response.single, 1);
      expect(_stringOf(files.single, 1), 'users.proto');
    });

    test('holds the file of a message of a contract', () async {
      final answer = await _ask(server, _fileOfSymbol('users.v1.User'));

      final response = _bytesOf(answer, 4);
      final files = _bytesOf(response.single, 1);
      expect(_stringOf(files.single, 1), 'users.proto');
    });

    test('answers with a problem when the symbol is unknown', () async {
      final answer = await _ask(server, _fileOfSymbol('users.v1.Nope'));

      expect(_bytesOf(answer, 7), hasLength(1));

      final error = _bytesOf(answer, 7).single;
      expect(_numberOf(error, 1), 5);
      expect(_stringOf(error, 2), contains('users.v1.Nope'));
    });

    test('does not list the service of the reflection itself', () async {
      final answer = await _ask(server, _listServices());

      final list = _bytesOf(answer, 6);
      final services = _bytesOf(list.single, 1);
      expect(services, hasLength(1));
      expect(_stringOf(services.single, 1), isNot(reflectionServiceV1));
    });

    test('is not served when the server does not want it', () async {
      final other = Laska();
      other.grpc.add(
        GrpcService(
          name: 'users.v1.UsersService',
          methods: <String, GrpcHandler>{
            'GetUser': (bytes) async => bytes,
          },
          descriptor: _descriptor(),
        ),
      );
      final silent = await serveGrpc(
        other,
        address: '127.0.0.1',
        port: 0,
        reflection: false,
      );
      addTearDown(silent.stop);

      final channel = grpc.ClientChannel(
        '127.0.0.1',
        port: silent.port,
        options: const grpc.ChannelOptions(
          credentials: grpc.ChannelCredentials.insecure(),
        ),
      );
      addTearDown(channel.shutdown);

      final call = channel.createCall<List<int>, List<int>>(
        grpc.ClientMethod<List<int>, List<int>>(
          '/$reflectionServiceV1/$reflectionMethod',
          (List<int> value) => value,
          (List<int> value) => value,
        ),
        Stream<List<int>>.value(_listServices()),
        grpc.CallOptions(),
      );

      await expectLater(call.response.single, throwsA(isA<grpc.GrpcError>()));
    });
  });
}
