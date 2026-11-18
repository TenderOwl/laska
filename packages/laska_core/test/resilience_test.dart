import 'dart:async';
import 'dart:convert';

import 'package:laska_core/laska_core.dart';
import 'package:test/test.dart';

/// A transport that answers what the test tells it to.
class _FakeTransport implements ServiceTransport {
  _FakeTransport(this.answers);

  /// The answers of the calls, one after the other.
  final List<TransportResponse> answers;

  /// The requests the transport received.
  final List<TransportRequest> requests = <TransportRequest>[];

  @override
  BodyFormat get bodyFormat => BodyFormat.json;

  @override
  Uri buildUri(String restPath, String rpcPath) => Uri.parse(restPath);
  @override
  Future<TransportResponse> send(TransportRequest request) async {
    requests.add(request);
    if (answers.isEmpty) {
      return TransportResponse(statusCode: 200);
    }
    return answers.removeAt(0);
  }

  @override
  Future<void> close() async {}
}

/// A transport that always fails.
class _FailingTransport implements ServiceTransport {
  @override
  BodyFormat get bodyFormat => BodyFormat.json;

  @override
  Uri buildUri(String restPath, String rpcPath) => Uri.parse(restPath);
  @override
  Future<TransportResponse> send(TransportRequest request) async {
    throw const SocketFailure('the dependency is down');
  }

  @override
  Future<void> close() async {}
}

/// A failure of the network.
class SocketFailure implements Exception {
  const SocketFailure(this.message);

  final String message;
}

TransportRequest _request() => TransportRequest(
      method: 'GET',
      uri: Uri.parse('http://localhost:8080/v1/users'),
    );

void main() {
  group('RetryPolicy', () {
    test('grows the backoff exponentially and caps it', () {
      const policy = RetryPolicy(
        initialBackoff: Duration(milliseconds: 100),
        maxBackoff: Duration(milliseconds: 500),
        jitter: false,
      );

      expect(policy.backoffFor(1), const Duration(milliseconds: 100));
      expect(policy.backoffFor(2), const Duration(milliseconds: 200));
      expect(policy.backoffFor(3), const Duration(milliseconds: 400));
      expect(policy.backoffFor(4), const Duration(milliseconds: 500));
    });

    test('randomises the backoff when the jitter is on', () {
      const policy = RetryPolicy(
        initialBackoff: Duration(milliseconds: 100),
        maxBackoff: Duration(milliseconds: 100),
      );

      final backoffs = <Duration>{
        for (var i = 0; i < 20; i++) policy.backoffFor(1),
      };

      expect(backoffs.length, greaterThan(1));
      expect(
        backoffs.every(
          (backoff) =>
              backoff >= Duration.zero &&
              backoff <= const Duration(milliseconds: 100),
        ),
        isTrue,
      );
    });

    test('honours the retry after of the dependency', () {
      const policy = RetryPolicy(maxBackoff: Duration(seconds: 30));

      expect(
        policy.backoffFor(1, retryAfter: const Duration(seconds: 2)),
        const Duration(seconds: 2),
      );
      expect(
        policy.backoffFor(1, retryAfter: const Duration(minutes: 5)),
        const Duration(seconds: 30),
      );
    });

    test('retries only the statuses it knows', () {
      const policy = RetryPolicy();

      expect(policy.shouldRetryStatus(503), isTrue);
      expect(policy.shouldRetryStatus(429), isTrue);
      expect(policy.shouldRetryStatus(404), isFalse);
      expect(policy.shouldRetryStatus(null), isTrue);
    });
  });

  group('Dependency', () {
    test('retries a failed idempotent call', () async {
      final transport = _FakeTransport(<TransportResponse>[
        TransportResponse(statusCode: 503),
        TransportResponse(statusCode: 503),
        TransportResponse(statusCode: 200, body: utf8.encode('{"ok":true}')),
      ]);

      final dependency = Dependency(
        name: 'users',
        transport: transport,
        policy: const DependencyPolicy(
          idempotent: true,
          retry: RetryPolicy(
            maxAttempts: 3,
            initialBackoff: Duration(milliseconds: 1),
            jitter: false,
          ),
        ),
      );

      final response = await dependency.call(_request());

      expect(response.statusCode, 200);
      expect(transport.requests, hasLength(3));
    });

    test('never retries a call that is not idempotent', () async {
      final transport = _FakeTransport(<TransportResponse>[
        TransportResponse(statusCode: 503),
        TransportResponse(statusCode: 200),
      ]);

      final dependency = Dependency(
        name: 'users',
        transport: transport,
        policy: const DependencyPolicy(
          retry: RetryPolicy(
            maxAttempts: 3,
            initialBackoff: Duration(milliseconds: 1),
          ),
        ),
      );

      await expectLater(
        dependency.call(_request()),
        throwsA(isA<DependencyFailure>()),
      );
      expect(transport.requests, hasLength(1));
    });

    test('does not retry a status the policy does not know', () async {
      final transport = _FakeTransport(<TransportResponse>[
        TransportResponse(statusCode: 404),
        TransportResponse(statusCode: 200),
      ]);

      final dependency = Dependency(
        name: 'users',
        transport: transport,
        policy: const DependencyPolicy(
          idempotent: true,
          retry: RetryPolicy(
            maxAttempts: 3,
            initialBackoff: Duration(milliseconds: 1),
          ),
        ),
      );

      await expectLater(
        dependency.call(_request()),
        throwsA(isA<DependencyFailure>()),
      );
      expect(transport.requests, hasLength(1));
    });

    test('reports the failure of the dependency', () async {
      final transport = _FakeTransport(<TransportResponse>[
        TransportResponse(statusCode: 500, body: utf8.encode('boom')),
      ]);

      final dependency = Dependency(
        name: 'users',
        transport: transport,
        policy: const DependencyPolicy(idempotent: false),
      );

      await expectLater(
        dependency.call(_request()),
        throwsA(
          isA<DependencyFailure>()
              .having((error) => error.statusCode, 'statusCode', 500)
              .having((error) => error.body, 'body', 'boom')
              .having((error) => error.dependency, 'dependency', 'users'),
        ),
      );
    });

    test('turns a timeout into a timeout of the dependency', () async {
      final dependency = Dependency(
        name: 'users',
        transport: _SlowTransport(),
        policy: const DependencyPolicy(
          timeout: Duration(milliseconds: 20),
          idempotent: false,
        ),
      );

      await expectLater(
        dependency.call(_request()),
        throwsA(isA<DependencyTimeoutException>()),
      );
    });

    test('turns a network failure into a failure of the dependency', () async {
      final dependency = Dependency(
        name: 'users',
        transport: _FailingTransport(),
        policy: const DependencyPolicy(idempotent: false),
      );

      await expectLater(
        dependency.call(_request()),
        throwsA(
          isA<DependencyFailure>()
              .having((error) => error.statusCode, 'statusCode', isNull),
        ),
      );
    });

    test('opens the circuit of a failing dependency', () async {
      final dependency = Dependency(
        name: 'users',
        transport: _FailingTransport(),
        policy: const DependencyPolicy(
          idempotent: false,
          circuitBreaker: CircuitBreakerPolicy(
            failureThreshold: 3,
            failureRatio: 0.5,
            minimumCalls: 3,
            cooldown: Duration(seconds: 5),
          ),
        ),
      );

      final stopwatch = Stopwatch()..start();
      for (var i = 0; i < 3; i++) {
        await expectLater(
          dependency.call(_request()),
          throwsA(isA<DependencyFailure>()),
        );
      }

      await expectLater(
        dependency.call(_request()),
        throwsA(isA<CircuitOpenException>()),
      );
      stopwatch.stop();

      expect(stopwatch.elapsed, lessThan(const Duration(seconds: 5)));
      expect(dependency.circuitBreaker!.state, CircuitState.open);
    });
  });

  group('CircuitBreaker', () {
    test('opens when the failures pass the ratio', () async {
      final breaker = CircuitBreaker(
        'users',
        const CircuitBreakerPolicy(
          failureThreshold: 2,
          failureRatio: 0.5,
          minimumCalls: 2,
          cooldown: Duration(seconds: 5),
        ),
      );

      await expectLater(
        breaker.call(() async => throw StateError('nope')),
        throwsA(isA<StateError>()),
      );
      await expectLater(
        breaker.call(() async => throw StateError('nope')),
        throwsA(isA<StateError>()),
      );

      expect(breaker.state, CircuitState.open);
      await expectLater(
        breaker.call(() async => 'never'),
        throwsA(isA<CircuitOpenException>()),
      );
    });

    test('lets a probe through after the cooldown', () async {
      var now = DateTime(2026);
      final breaker = CircuitBreaker(
        'users',
        const CircuitBreakerPolicy(
          failureThreshold: 1,
          failureRatio: 1,
          minimumCalls: 1,
          cooldown: Duration(seconds: 5),
        ),
        clock: () => now,
      );

      await expectLater(
        breaker.call(() async => throw StateError('nope')),
        throwsA(isA<StateError>()),
      );
      expect(breaker.state, CircuitState.open);

      now = now.add(const Duration(seconds: 6));
      final result = await breaker.call(() async => 'ok');

      expect(result, 'ok');
      expect(breaker.state, CircuitState.closed);
    });

    test('opens again when the probe fails', () async {
      var now = DateTime(2026);
      final breaker = CircuitBreaker(
        'users',
        const CircuitBreakerPolicy(
          failureThreshold: 1,
          failureRatio: 1,
          minimumCalls: 1,
          cooldown: Duration(seconds: 5),
        ),
        clock: () => now,
      );

      await expectLater(
        breaker.call(() async => throw StateError('nope')),
        throwsA(isA<StateError>()),
      );

      now = now.add(const Duration(seconds: 6));
      await expectLater(
        breaker.call(() async => throw StateError('nope')),
        throwsA(isA<StateError>()),
      );

      expect(breaker.state, CircuitState.open);
    });
  });

  group('Bulkhead', () {
    test('lets the calls of the limit run at the same time', () async {
      final bulkhead = Bulkhead(
        'users',
        const BulkheadPolicy(maxConcurrent: 2, maxQueue: 1),
      );

      final started = <int>[];
      final gate = Completer<void>();

      final first = bulkhead.run(() async {
        started.add(1);
        await gate.future;
      });
      final second = bulkhead.run(() async {
        started.add(2);
        await gate.future;
      });

      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(started, hasLength(2));
      expect(bulkhead.active, 2);

      gate.complete();
      await Future.wait(<Future<void>>[first, second]);
      expect(bulkhead.active, 0);
    });

    test('fails fast when the bulkhead is full', () async {
      final bulkhead = Bulkhead(
        'users',
        const BulkheadPolicy(
          maxConcurrent: 1,
          maxQueue: 0,
          acquireTimeout: Duration(milliseconds: 10),
        ),
      );

      final gate = Completer<void>();
      final running = bulkhead.run(() => gate.future);

      await expectLater(
        bulkhead.run(() async {}),
        throwsA(isA<BulkheadFullException>()),
      );

      gate.complete();
      await running;
    });
  });

  group('the idempotency middleware', () {
    test('answers a repeated request with the first answer', () async {
      final store = IdempotencyStore();
      var calls = 0;

      final middleware = idempotencyMiddleware(store: store);
      final request = Request(
        method: 'POST',
        path: '/v1/users',
        uri: '/v1/users',
        query: const <String, String>{},
        headers: const <String, String>{'idempotency-key': 'key-1'},
      );

      final first = await middleware(request, () async {
        calls++;
        return Response.json(<String, dynamic>{'id': 'u_1'});
      });

      expect(calls, 1);
      expect(request.idempotencyKey, 'key-1');

      final second = await middleware(request, () async {
        calls++;
        return Response.json(<String, dynamic>{'id': 'u_2'});
      });

      expect(calls, 1);
      expect(second.status, first.status);
      expect(second.text, first.text);
      expect(second.headers['idempotency-replayed'], 'true');
    });

    test('calls the handler again for another key', () async {
      var calls = 0;
      final middleware = idempotencyMiddleware();

      for (final key in <String>['key-1', 'key-2']) {
        final request = Request(
          method: 'POST',
          path: '/v1/users',
          uri: '/v1/users',
          query: const <String, String>{},
          headers: <String, String>{'idempotency-key': key},
        );
        await middleware(request, () async {
          calls++;
          return Response.json(<String, dynamic>{'id': 'u_$calls'});
        });
      }

      expect(calls, 2);
    });

    test('creates a key that is not used twice', () {
      final keys = <String>{for (var i = 0; i < 100; i++) newIdempotencyKey()};

      expect(keys, hasLength(100));
    });
  });

  group('ServiceDiscovery', () {
    test('reads the services of the environment', () {
      final discovery = ServiceDiscovery.fromEnvironment(<String, String>{
        'LASKA_SERVICES':
            'users=http://localhost:8080, orders=http://localhost:8081',
        'BILLING_URL': 'http://localhost:8082',
      });

      expect(
          discovery.names, containsAll(<String>['users', 'orders', 'BILLING']));
      expect(
        discovery.resolve('users'),
        Uri.parse('http://localhost:8080'),
      );
    });

    test('reports a service it does not know', () {
      final discovery = ServiceDiscovery.fromEnvironment(<String, String>{});

      expect(
        () => discovery.resolve('users'),
        throwsA(isA<ServiceNotFoundException>()),
      );
    });
  });

  group('the status mapping', () {
    test('maps the HTTP statuses to the statuses of gRPC', () {
      expect(grpcStatusOf(200), GrpcStatus.ok);
      expect(grpcStatusOf(404), GrpcStatus.notFound);
      expect(grpcStatusOf(503), GrpcStatus.unavailable);
      expect(grpcStatusOf(504), GrpcStatus.deadlineExceeded);
    });

    test('maps the statuses of gRPC to the HTTP statuses', () {
      expect(httpStatusOfGrpc(GrpcStatus.ok), 200);
      expect(httpStatusOfGrpc(GrpcStatus.notFound), 404);
      expect(httpStatusOfGrpc(GrpcStatus.unavailable), 503);
    });

    test('maps the errors of the framework to the HTTP statuses', () {
      expect(
        httpStatusOfError(CircuitOpenException('users', Duration.zero)),
        503,
      );
      expect(
        httpStatusOfError(DependencyTimeoutException('users', Duration.zero)),
        504,
      );
      expect(
        httpStatusOfError(BulkheadFullException('users')),
        503,
      );
      expect(
        httpStatusOfError(
          DependencyFailure('users', statusCode: 418, message: 'teapot'),
        ),
        418,
      );
    });
  });
}

/// A transport that never answers in time.
class _SlowTransport implements ServiceTransport {
  @override
  BodyFormat get bodyFormat => BodyFormat.json;

  @override
  Uri buildUri(String restPath, String rpcPath) => Uri.parse(restPath);
  @override
  Future<TransportResponse> send(TransportRequest request) async {
    await Future<void>.delayed(const Duration(seconds: 5));
    return TransportResponse(statusCode: 200);
  }

  @override
  Future<void> close() async {}
}
