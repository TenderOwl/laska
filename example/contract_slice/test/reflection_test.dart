import 'dart:io';

import 'package:contract_slice_example/generated/users.pb.dart';
import 'package:contract_slice_example/service.dart';
import 'package:laska_core/laska_core.dart';
import 'package:test/test.dart';

/// The path of the tool `grpcurl`, if it is installed.
///
/// The tool is the one of the ecosystem that reads the reflection of a gRPC
/// server. The path is taken from the environment when it is set, so a machine
/// that keeps the tool out of the path still runs the test.
String? _grpcurl() {
  final fromEnvironment = Platform.environment['GRPCURL'];
  if (fromEnvironment != null && fromEnvironment.isNotEmpty) {
    return fromEnvironment;
  }

  try {
    final result = Process.runSync('grpcurl', <String>['--version']);
    if (result.exitCode == 0) {
      return 'grpcurl';
    }
  } on ProcessException {
    return null;
  }

  return null;
}

/// The answer of `grpcurl` with the arguments [arguments].
///
/// The [flags] of the tool come before the address of the server, the way the
/// tool reads them.
Future<ProcessResult> _grpcurlRun(
  String grpcurl,
  int port, {
  List<String> flags = const <String>[],
  List<String> arguments = const <String>[],
}) =>
    Process.run(
      grpcurl,
      <String>[...flags, '-plaintext', '127.0.0.1:$port', ...arguments],
    );

void main() {
  group('the reflection of the gRPC server of a contract', () {
    late Laska app;
    late GrpcServer server;

    setUp(() async {
      app = Laska();
      registerUsersService(app, UsersServiceImpl());
      server = await serveGrpc(app, address: '127.0.0.1', port: 0);
    });

    tearDown(() async {
      await server.stop();
    });

    test('a tool of the ecosystem lists the services of the server', () async {
      final grpcurl = _grpcurl();
      if (grpcurl == null) {
        markTestSkipped('The tool "grpcurl" is not installed.');
        return;
      }

      final result = await _grpcurlRun(
        grpcurl,
        server.port,
        arguments: <String>['list'],
      );

      expect(result.exitCode, 0, reason: result.stderr.toString());
      expect(result.stdout, contains('users.v1.UsersService'));
    });

    test('a tool of the ecosystem describes the methods of a service',
        () async {
      final grpcurl = _grpcurl();
      if (grpcurl == null) {
        markTestSkipped('The tool "grpcurl" is not installed.');
        return;
      }

      final result = await _grpcurlRun(
        grpcurl,
        server.port,
        arguments: <String>['describe', 'users.v1.UsersService'],
      );

      expect(result.exitCode, 0, reason: result.stderr.toString());
      expect(result.stdout, contains('GetUser'));
      expect(result.stdout, contains('ListUsers'));
      expect(result.stdout, contains('CreateUser'));
    });

    test('a tool of the ecosystem calls a method through the reflection',
        () async {
      final grpcurl = _grpcurl();
      if (grpcurl == null) {
        markTestSkipped('The tool "grpcurl" is not installed.');
        return;
      }

      final result = await _grpcurlRun(
        grpcurl,
        server.port,
        flags: <String>['-d', '{"id":"u_1"}'],
        arguments: <String>['users.v1.UsersService.GetUser'],
      );

      expect(result.exitCode, 0, reason: result.stderr.toString());
      expect(result.stdout, contains('ada@example.com'));
      expect(result.stdout, contains('Ada Lovelace'));
    });
  });
}
