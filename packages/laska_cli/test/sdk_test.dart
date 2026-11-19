import 'dart:io';

import 'package:laska_cli/src/sdk.dart';
import 'package:test/test.dart';

void main() {
  group('the version of the SDK of a package', () {
    late Directory workspace;

    setUp(() {
      workspace = Directory.systemTemp.createTempSync('laska_sdk_');
    });

    tearDown(() {
      workspace.deleteSync(recursive: true);
    });

    void writePubspec(String content, {String? inside}) {
      final directory =
          inside == null ? workspace : Directory('${workspace.path}/$inside');
      directory.createSync(recursive: true);
      File('${directory.path}/pubspec.yaml').writeAsStringSync(content);
    }

    test('reads the lower bound of the constraint of the package', () {
      writePubspec('''
name: shop_service
environment:
  sdk: ^3.6.0
''');

      expect(sdkVersionOf(workspace.path)?.toString(), '3.6.0');
    });

    test('reads the lower bound of a range', () {
      writePubspec('''
name: shop_service
environment:
  sdk: '>=3.6.0 <4.0.0'
''');

      expect(sdkVersionOf(workspace.path)?.toString(), '3.6.0');
    });

    test('finds the package above the directory', () {
      writePubspec('''
name: shop_service
environment:
  sdk: ^3.14.0
''', inside: 'lib/generated');

      expect(sdkVersionOf('${workspace.path}/lib/generated')?.toString(),
          '3.14.0');
    });

    test('reads nothing when there is no pubspec', () {
      expect(sdkVersionOf(workspace.path), isNull);
    });

    test('reads nothing when the pubspec holds no constraint', () {
      writePubspec('''
name: shop_service
''');

      expect(sdkVersionOf(workspace.path), isNull);
    });
  });
}
