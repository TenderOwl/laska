# Changelog

## Unreleased

- The well-known types of protobuf are part of the runtime: `ProtoTimestamp`,
  `ProtoDuration`, `ProtoAny` and `ProtoEmpty`. They know the wire format and
  the JSON of the protocol buffers, so every service of a contract speaks of
  them with the same Dart types.
- The gRPC server of a service: `GrpcServer` serves the services registered on
  the application, and `serveGrpc(app)` starts one. A call goes through the
  middleware of the application, and an error of the service keeps its status:
  a `HttpException(404, ...)` is answered with the status `NOT_FOUND` of the
  protocol of gRPC.
- `run(app, grpcPort: 50051)` starts the gRPC server of the application next
  to the HTTP one.
- The registry of the gRPC services of an application is `app.grpc`.

## 0.2.0

- A boolean is written with its value now. The writer of the wire format wrote
  the value `1` whatever the boolean was, so every `false` of a contract came
  back as `true`.

## 0.1.0

- The first release of the runtime: the routing, the middleware, the request and
  the response, the problem documents, the configuration, the logger, the data
  layer, the supervisor and the telemetry.
- The authentication of the callers: the tokens (JWT with HS, RS and ES), the
  JWKS with the rotation of the keys, the API keys, the sessions with the
  defence against the fixation, and the rate limiting.
- The performance of the hot path: the tables of the router are built when a
  route is registered, the chain of the middleware is built once and kept, and
  the body of a request is read into a buffer that comes from a pool.

The history of the project lives in the
[changelog of the repository](https://github.com/tenderowl/laska/blob/main/CHANGELOG.md).
