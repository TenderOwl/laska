import 'dart:io';

import 'package:laska_contracts/laska_contracts.dart';
import 'package:test/test.dart';

/// The path of the Go module of the SDK of the example.
const String _module = 'github.com/TenderOwl/laska/example/contract_slice/go';

/// The name of the Go package of the SDK of the example.
const String _package = 'users';

void main() {
  test('the SDK of the example holds the code the generator writes', () async {
    final root = Directory.current;
    final sources = await readProtoDirectory('${root.path}/api');
    final contract = ContractCompiler().build(sources);
    final files = GoGenerator(
      contract,
      module: _module,
      package: _package,
    ).generate();

    for (final file in files) {
      final path = File('${root.path}/go/${file.path}');
      expect(
        path.existsSync(),
        isTrue,
        reason: 'the SDK of the example has no file "${file.path}"',
      );
      expect(
        path.readAsStringSync(),
        file.content,
        reason:
            'the file "${file.path}" of the SDK of the example is not the code '
            'the generator writes',
      );
    }
  });

  test('the SDK of the example names the module of the repository', () {
    final module = File(
      '${Directory.current.path}/go/go.mod',
    ).readAsStringSync();

    expect(module, contains('module $_module'));
  });
}
