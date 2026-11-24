# Changelog

## Unreleased

- The harness ships a fake cache store: `FakeCacheStore` keeps the values in
  memory and records the calls of the service — the keys that were read and
  written, the hits and the misses — so a test asserts what the service
  cached. The fake fails on demand, so a test covers the service that
  survives a broken cache.

## 0.3.0

- The harness is published with the version of the framework, so a project can
  depend on the version of the framework it uses.

## 0.2.0

- The harness is published again with the version of the framework, so a
  project can depend on the version of the framework it uses.

## 0.1.0

- The first release of the test harness: the in-process client, the expectation
  helpers, the database helpers, the fake tracer and the fake transport.

The history of the project lives in the
[changelog of the repository](https://github.com/tenderowl/laska/blob/main/CHANGELOG.md).
