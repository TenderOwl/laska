# laska_contracts

The contract pipeline of [Laska](https://github.com/tenderowl/laska): a pure-Dart
parser of the `.proto` files, a generator of the Dart code, an exporter of the
OpenAPI document and the check of the breaking changes.

```dart
import 'package:laska_contracts/laska_contracts.dart';

final compiler = ContractCompiler(title: 'Users API');
final result = compiler.compile(sources);

await writeGeneratedFiles(result, 'lib/generated');
```

## What it holds

- **The parser** — the proto3 files are parsed in pure Dart, so no native
  toolchain is needed to compile a contract.
- **The generator** — the message classes, the service interface, the REST
  projection, the typed client and the OpenAPI 3.1 document.
- **The diff** — the breaking changes of a contract, with the rules of Buf.
- **The matrix** — which client of which version works against which server of
  which version.
- **The versions** — the semver policy of the contracts and the version of an
  API.

## The documentation

The guide of the contracts lives in
[docs/contracts.md](https://github.com/tenderowl/laska/blob/main/docs/contracts.md).

## The licence

MIT — see [LICENSE](LICENSE).
