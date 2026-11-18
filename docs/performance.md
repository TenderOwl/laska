# The performance of the hot path

The hot path of Laska is the way a request goes through the runtime: it is
read from the socket, routed, handed to the middleware and to the handler, and
the answer goes back. Everything else — the contract, the code generation, the
telemetry — happens outside of that path.

This page describes what the hot path does, what it is allowed to allocate and
how to measure it.

## The budget

The budget of the hot path is not a number of nanoseconds: that would depend
on the machine, on the load and on the Dart version. It is a number of objects
the runtime may create for a request.

| Step | Objects created for a request |
|---|---|
| The request | The request itself, the map of its headers, the map of its query |
| The routing | The match of the route, and the map of its parameters — only when the route captures one |
| The middleware | The context, and one future per level of the chain |
| The answer | The response, its headers and its body |

The rules that hold the runtime to it:

- a static route answers without building a map of parameters — the empty map
  is shared;
- a route that does not match builds no map at all;
- the chain of the middleware of a route is built once and kept, so a request
  does not rebuild it;
- the request is not copied for the parameters of the route: the dispatcher
  writes them into the request it was given;
- the body of a request is read into a buffer that comes from a pool and goes
  back to it when the body was read.

Those rules are held by the tests of `packages/laska_core/test/performance_test.dart`
and `packages/laska_core/test/buffers_test.dart`, so a change that breaks them
fails the pipeline.

## The tables of the router

The router builds its tables when a route is registered, not when a request
arrives:

- the static routes are held per method, so a static route is found with two
  map lookups and without touching the other routes;
- the routes with parameters are held per method too, so a request only walks
  the routes that may answer it;
- the specificity of a route — the score that decides which route wins — is
  computed once, when the route is registered;
- the expressions of the constraints are compiled once. A constraint of the
  kind `int` is checked without an expression at all, because the check is
  faster than the expression.

The result of the pass, measured with `dart run tool/benchmark.dart` on the
machine of the author:

| Lookup | Before | After |
|---|---|---|
| A static route | 0.18 µs | 0.09 µs |
| A route with a parameter | 1.07 µs | 0.76 µs |
| A route with a constraint | 1.66 µs | 0.71 µs |

The numbers are relative: they tell how much a change of the hot path costs,
not how fast a service is on a given machine.

## The buffers of the bodies

The body of a request used to be read with the decoder of `dart:convert`, which
builds a buffer of its own for every request. The runtime now reads the body
into a buffer of a pool:

```dart
final buffer = BodyBuffer(_pool);
await for (final chunk in httpRequest) {
  buffer.add(chunk);
}
try {
  return utf8.decode(buffer.take());
} finally {
  buffer.release();
}
```

The buffer grows as the body arrives, so a body of any size is read, and it
goes back to the pool when the body was decoded. A body that is bigger than
64 KiB is not kept by the pool, so a huge upload does not hold its memory for
ever.

Reading a body of 2 KiB went from 6.3 µs to 3.7 µs.

## The benchmark

```console
$ dart run tool/benchmark.dart
router: a static route                  0.09 us/op     11363636 op/s
router: a route with a parameter        0.76 us/op     1315789 op/s
router: a route with a constraint       0.71 us/op     1408450 op/s
dispatch: a static route                3.72 us/op      268504 op/s
dispatch: a route with a parameter      3.50 us/op      285776 op/s
```

The benchmark runs in process and covers the routing and the dispatch with the
middleware of a real service — the request id, the tracing, the metrics and the
log. It does not open a socket, so it measures the framework and not the
network.

The number of iterations may be given as an argument:

```console
$ dart run tool/benchmark.dart 1000000
```

The benchmark is a tool of the repository, not a test: a test that holds the
runtime to a number of nanoseconds would fail on a busy machine. The budget
that the pipeline holds is the one of the objects, and it is covered by the
tests.

## What is not measured

The benchmark does not cover:

- the socket and the operating system, which dominate the answer of a real
  service;
- the database, which dominates a service that reads or writes;
- the calls to the other services, which are bounded by the network and by the
  policy of the calls;
- the telemetry, which is only exported when the environment asks for it.

A change of the hot path is measured with the benchmark and checked with the
tests of the budget. A change of the rest of the runtime is measured by the
tests of the behaviour.
