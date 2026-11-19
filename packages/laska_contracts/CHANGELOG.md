# Changelog

## Unreleased

- The parser reads the whole of proto3 a service needs: `map` fields, groups of
  a `oneof`, and messages and enums that are declared inside a message. The
  types that are written without a qualifier are resolved the way protobuf
  resolves them.
- A map is generated as a `Map<K, V>`, a group of a `oneof` as a sealed class
  whose members are classes of their own, and a type declared inside a message
  as a class named after the scope it was declared in.
- The OpenAPI document describes the new types, and the check of the breaking
  changes knows the groups of a `oneof`.
- A field that may be absent is generated as a valid Dart type. The code was
  `<Type>?`, which does not compile.

## 0.1.0

- The first release of the contract pipeline: the pure-Dart parser of the
  `.proto` files, the generator of the Dart code — the message classes, the
  service interface, the REST projection and the typed client — the exporter of
  the OpenAPI 3.1 document, the check of the breaking changes and the lint of
  the rules of the framework.
- The policy of the versions: the semver of the packages and of the contracts,
  and the version of an API in the name of the package of the contract.
- The matrix of the compatibility: which client of which version works against
  which server of which version.

The history of the project lives in the
[changelog of the repository](https://github.com/tenderowl/laska/blob/main/CHANGELOG.md).
