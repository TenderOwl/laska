# Changelog

## Unreleased

- The well-known types of protobuf are types a contract may use: the moment of
  a day, the span of time, a value of any type and the empty message. They are
  compiled into the types of the runtime — `ProtoTimestamp`, `ProtoDuration`,
  `ProtoAny` and `ProtoEmpty` — and the JSON of them is the JSON of protobuf:
  a timestamp is the time in the format of RFC 3339 and a duration is the
  number of seconds.
- The imports between the files of a contract are resolved: the path of an
  import is the path of a file of the contract, taken from the directory of the
  file that imports it, and a type of a file that is not imported is an error.
  A public import passes the types of the imported file to the files that
  import the file that imports it.
- A field that may be absent is read out of the JSON. The message of an
  optional field was never built, so a contract with an optional message
  produced code that did not compile.

## 0.2.0

- The compiler takes the version of the language the generated code is written
  for. The style of the formatter depends on it, and it has to be the style of
  the package the code goes into: `dart format` picks the style by the version
  of the SDK the package declares.
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
