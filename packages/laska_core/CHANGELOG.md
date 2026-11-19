# Changelog

## Unreleased

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
