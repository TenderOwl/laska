import 'dart:io';

import 'package:laska_core/laska_core.dart';
import 'package:test/test.dart';

void main() {
  group('the directory of a package', () {
    test('is the directory above the lib of the package', () async {
      final directory = await packageDirectory(
        Uri.parse('package:laska_core/laska_core.dart'),
      );

      expect(directory, isNotNull);
      expect(
        File('$directory/pubspec.yaml').existsSync(),
        isTrue,
        reason: 'the package holds its pubspec',
      );
    });

    test('is unknown for a package the runtime does not know', () async {
      final directory = await packageDirectory(
        Uri.parse('package:not_a_package_at_all/nothing.dart'),
      );

      expect(directory, isNull);
    });
  });

  group('the directory of a frontend', () {
    final packageUri = Uri.parse('package:laska_core/laska_core.dart');

    test('is the directory of the files inside of the package', () async {
      final package = await packageDirectory(packageUri);

      final directory = await frontendDirectory(packageUri: packageUri);

      expect(directory, '$package${Platform.pathSeparator}web');
    });

    test('may be named by the environment', () async {
      final package = await packageDirectory(packageUri);

      final directory = await frontendDirectory(
        packageUri: packageUri,
        configured: 'public',
      );

      // A relative path is read against the package as well.
      expect(directory, '$package${Platform.pathSeparator}public');
    });

    test('takes an absolute path of the environment as it is', () async {
      final absolute = Directory.systemTemp.path;

      final directory = await frontendDirectory(
        packageUri: packageUri,
        configured: absolute,
      );

      expect(directory, absolute);
    });

    test('falls back to the directory of the process without a package',
        () async {
      final directory = await frontendDirectory(
        packageUri: Uri.parse('package:not_a_package_at_all/nothing.dart'),
      );

      expect(directory, 'web');
    });
  });
}
