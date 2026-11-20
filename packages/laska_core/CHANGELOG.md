# Changelog

## Unreleased

- The gRPC transport sends the headers of a request as the metadata of the
  call. The names of the metadata of gRPC are in lower case, so the names of
  the headers are lower-cased as well, and the headers that belong to the
  protocol itself — `accept` and `content-type` — are left out: the content
  type of a gRPC call is the one of the protocol.
- The files of a directory are served by the runtime: `app.staticFiles(prefix,
  directory)` mounts a directory under a prefix. A file is served with the
  content type of its extension, with the validators of the cache — an `ETag`,
  a `Last-Modified` and a `304` without a body — and with the header
  `X-Content-Type-Options: nosniff`. The path of the request is decoded by the
  runtime, and a path that points outside of the directory is refused.
- `Response.html` and `ctx.html` build an answer with the content type of a
  document of HTML: `text/html; charset=utf-8`.

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
- The gRPC transport and the gRPC server wait for the streams of the calls
  that finished to be closed before they close the connection. The client of
  `package:grpc` closes them in the background, and `package:http2` asserts
  that a connection does not end with an open stream, so a shutdown that is
  too early took the assertion with it.
- The gRPC server answers the calls of the methods a service does not have
  itself. The protocol of gRPC answers such a call and keeps the stream of it
  open until the client goes away, so the connection of the service could not
  be closed cleanly.

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
