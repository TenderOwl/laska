import 'package:laska_core/laska_core.dart';
import 'package:laska_test/laska_test.dart';
import 'package:test/test.dart';

void main() {
  group('TestTransport', () {
    test('answers with the responses the test prepared', () async {
      final transport = TestTransport()
        ..enqueueResponse(200, body: <String, Object>{'id': 'u_1'})
        ..enqueueResponse(404);

      final first = await transport.send(
        TransportRequest(method: 'GET', uri: Uri.parse('http://test.local/v1')),
      );
      final second = await transport.send(
        TransportRequest(method: 'GET', uri: Uri.parse('http://test.local/v1')),
      );

      expect(first.statusCode, 200);
      expect(first.text, '{"id":"u_1"}');
      expect(second.statusCode, 404);
    });

    test('records the requests it received', () async {
      final transport = TestTransport()
        ..alwaysRespond(
          TransportResponse(statusCode: 200),
        );

      await transport.send(
        TransportRequest(
          method: 'POST',
          uri: Uri.parse('http://test.local/v1/users'),
          headers: <String, String>{'idempotency-key': 'key_1'},
        ),
      );

      expect(transport.callCount, 1);
      expect(transport.requests.single.method, 'POST');
      expect(transport.requests.single.headers['idempotency-key'], 'key_1');
    });

    test('fails with the error the test prepared', () async {
      final transport = TestTransport()..enqueueError(const SocketFailure());

      await expectLater(
        transport.send(
          TransportRequest(method: 'GET', uri: Uri.parse('http://test.local')),
        ),
        throwsA(isA<SocketFailure>()),
      );
    });

    test('answers with the handler when one is given', () async {
      final transport = TestTransport(
        handler: (request) async => TransportResponse(
          statusCode: 201,
          body: request.body,
        ),
      );

      final response = await transport.send(
        TransportRequest(
          method: 'POST',
          uri: Uri.parse('http://test.local'),
          body: <int>[1, 2, 3],
        ),
      );

      expect(response.statusCode, 201);
      expect(response.body, <int>[1, 2, 3]);
    });

    test('refuses to answer when the test prepared nothing', () async {
      final transport = TestTransport();

      await expectLater(
        transport.send(
          TransportRequest(method: 'GET', uri: Uri.parse('http://test.local')),
        ),
        throwsA(isA<StateError>()),
      );
    });

    test('builds the address of a call', () {
      final transport = TestTransport();

      expect(
        transport.buildUri('/v1/users/u_1', '/users.v1.UsersService/GetUser'),
        Uri.parse('http://test.local/v1/users/u_1'),
      );
    });
  });
}

/// A failure of the network.
class SocketFailure implements Exception {
  const SocketFailure();
}
