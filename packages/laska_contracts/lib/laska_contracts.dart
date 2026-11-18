/// Contract tooling for Laska.
///
/// The package turns a `.proto` contract into the artefacts a service needs:
/// Dart message classes, a service interface, the REST projection of every
/// method, a typed client, an OpenAPI 3.1 document — and it can tell whether
/// two versions of a contract are compatible.
library;

export 'src/compatibility.dart';
export 'src/compile.dart';
export 'src/diff.dart';
export 'src/generator/dart_generator.dart';
export 'src/generator/openapi_generator.dart';
export 'src/lint.dart';
export 'src/model.dart';
export 'src/naming.dart';
export 'src/parser.dart';
export 'src/types.dart';
export 'src/version.dart';
