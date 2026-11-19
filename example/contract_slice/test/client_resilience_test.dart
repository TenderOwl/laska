import 'dart:convert';

import 'package:contract_slice_example/generated/users.pb.dart';
import 'package:laska_core/laska_core.dart';
import 'package:laska_test/laska_test.dart';
import 'package:test/test.dart';

void main() {
  group('The policy of the contract', () {
    test('is visible in the generated code', () {
      expect(UsersServicePolicies.getUser.timeout, const Duration(seconds: 2));
      expect(UsersServicePolicies.getUser.retry.maxAttempts, 3);
      expect(
        UsersServicePolicies.getUser.retry.initialBackoff,
        const Duration(milliseconds: 100),
      );
      expect(UsersServicePolicies.getUser.idempotent, isTrue);
    });

    test('marks the calls that change something as not idempotent', () {
      expect(UsersServicePolicies.createUser.idempotent, isFalse);
    });
  });

  group('The generated client', () {
    test(
        'retries an idempotent call and gives up with the status of the '
        'dependency', () async {
      final transport = TestTransport();
      transport.alwaysRespond(TransportResponse(statusCode: 503));

      final client = UsersServiceClient(
        baseUrl: 'http://localhost:8080',
        transport: transport,
      );

      await expectLater(
        client.getUser(GetUserRequest(id: 'u_1')),
        throwsA(
          isA<LaskaApiException>().having(
            (error) => error.statusCode,
            'statusCode',
            503,
          ),
        ),
      );

      expect(transport.callCount, 3, reason: 'the call was retried twice');
    });

    test('never retries a call that is not idempotent', () async {
      final transport = TestTransport();
      transport.alwaysRespond(TransportResponse(statusCode: 503));

      final client = UsersServiceClient(
        baseUrl: 'http://localhost:8080',
        transport: transport,
      );

      await expectLater(
        client.createUser(
          CreateUserRequest(
            email: 'a@b.c',
            displayName: 'A B',
            role: UserRole.userRoleMember,
          ),
        ),
        throwsA(isA<LaskaApiException>()),
      );

      expect(transport.callCount, 1);
    });

    test(
      'sends an idempotency key with a call that is not idempotent',
      () async {
        final transport = TestTransport();
        transport.alwaysRespond(
          TransportResponse(
            statusCode: 200,
            body: utf8.encode(
              jsonEncode(<String, Object>{
                'id': 'u_1',
                'email': 'a@b.c',
                'displayName': 'A B',
                'role': 'USER_ROLE_MEMBER',
              }),
            ),
          ),
        );

        final client = UsersServiceClient(
          baseUrl: 'http://localhost:8080',
          transport: transport,
        );

        await client.createUser(
          CreateUserRequest(
            email: 'a@b.c',
            displayName: 'A B',
            role: UserRole.userRoleMember,
          ),
        );

        expect(
          transport.requests.single.headers['idempotency-key'],
          isNotEmpty,
        );
      },
    );
  });

  group('A dependency that is down', () {
    test('opens the circuit and fails fast instead of piling up', () async {
      final transport = TestTransport();
      transport.alwaysRespond(TransportResponse(statusCode: 503));

      final client = UsersServiceClient(
        baseUrl: 'http://localhost:8080',
        transport: transport,
        policy: const DependencyPolicy(
          circuitBreaker: CircuitBreakerPolicy(
            failureThreshold: 3,
            failureRatio: 1,
            minimumCalls: 1,
            window: Duration(seconds: 30),
            cooldown: Duration(seconds: 30),
          ),
        ),
      );

      final started = DateTime.now();

      // The first call spends its attempts and trips the breaker.
      await expectLater(
        client.getUser(GetUserRequest(id: 'u_1')),
        throwsA(isA<LaskaApiException>()),
      );

      // The next call does not reach the dependency at all: the circuit is
      // open, so the caller gets an answer straight away.
      final failed = DateTime.now();

      await expectLater(
        client.getUser(GetUserRequest(id: 'u_2')),
        throwsA(
          isA<LaskaApiException>().having(
            (error) => error.statusCode,
            'statusCode',
            503,
          ),
        ),
      );

      final elapsed = DateTime.now().difference(started).inMilliseconds;
      final fast = DateTime.now().difference(failed).inMilliseconds;

      expect(elapsed, lessThan(5000));
      expect(fast, lessThan(1000));
      expect(
        transport.callCount,
        3,
        reason: 'the open circuit stops the calls',
      );
    });

    test('answers with a timeout when the dependency is too slow', () async {
      final transport = TestTransport(
        handler: (request) async {
          await Future<void>.delayed(const Duration(milliseconds: 200));
          return TransportResponse(statusCode: 200);
        },
      );

      final client = UsersServiceClient(
        baseUrl: 'http://localhost:8080',
        transport: transport,
        policies: <String, DependencyPolicy>{
          'GetUser': const DependencyPolicy(
            timeout: Duration(milliseconds: 50),
            idempotent: true,
          ),
        },
      );

      await expectLater(
        client.getUser(GetUserRequest(id: 'u_1')),
        throwsA(
          isA<LaskaApiException>().having(
            (error) => error.statusCode,
            'statusCode',
            504,
          ),
        ),
      );
    });
  });
}
