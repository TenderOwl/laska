/// The recipe of the continuous integration of a project.
///
/// The recipe is a workflow of GitHub Actions that runs the checks of the
/// framework: the format, the analyzer, the tests, the lint of the contract
/// and the comparison of the contract with its baseline.
library;

/// The workflow of the continuous integration.
///
/// The [proto] directory holds the contract, the [base] and the [candidate]
/// directories hold the two versions of the contract when the project checks
/// that the contract stays compatible, and the [matrix] directory holds one
/// directory per version of the contract when the project writes the matrix of
/// the versions.
String renderCiRecipe({
  String proto = 'api',
  String? base,
  String? candidate,
  String? matrix,
  String name = 'laska',
}) {
  final buffer = StringBuffer()
    ..writeln('# The recipe of the continuous integration.')
    ..writeln('#')
    ..writeln('# It is written by "laska ci:recipe" and it may be changed.')
    ..writeln('name: $name')
    ..writeln()
    ..writeln('on:')
    ..writeln('  push:')
    ..writeln('  pull_request:')
    ..writeln()
    ..writeln('jobs:')
    ..writeln('  check:')
    ..writeln('    runs-on: ubuntu-latest')
    ..writeln('    steps:')
    ..writeln('      - uses: actions/checkout@v4')
    ..writeln()
    ..writeln('      - uses: dart-lang/setup-dart@v1')
    ..writeln('        with:')
    ..writeln('          sdk: stable')
    ..writeln()
    ..writeln('      - run: dart pub get')
    ..writeln('      - run: dart format --output=none --set-exit-if-changed .')
    ..writeln('      - run: dart analyze')
    ..writeln('      - run: dart test')
    ..writeln(
      '      - run: dart run laska_cli:laska contract lint --proto $proto',
    );

  if (base != null && candidate != null) {
    buffer.writeln(
      '      - run: dart run laska_cli:laska contract diff '
      '--base $base --candidate $candidate',
    );
  }

  if (matrix != null) {
    buffer.writeln(
      '      - run: dart run laska_cli:laska contract matrix '
      '--dir $matrix --out matrix.md',
    );
  }

  return buffer.toString();
}
