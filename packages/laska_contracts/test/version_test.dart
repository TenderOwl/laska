import 'package:laska_contracts/laska_contracts.dart';
import 'package:test/test.dart';

void main() {
  group('Version', () {
    test('reads a version out of its text', () {
      final version = Version.parse('1.2.3');

      expect(version.major, 1);
      expect(version.minor, 2);
      expect(version.patch, 3);
      expect(version.text, '1.2.3');
    });

    test('reads the pre-release and the build part', () {
      final version = Version.parse('1.0.0-rc.1+build.7');

      expect(version.isPreRelease, isTrue);
      expect(version.preRelease, 'rc.1');
      expect(version.build, 'build.7');
    });

    test('refuses a text that is not a version', () {
      expect(Version.tryParse('1.2'), isNull);
      expect(Version.tryParse('1.2.x'), isNull);
      expect(Version.tryParse(''), isNull);
      expect(() => Version.parse('nope'), throwsFormatException);
    });

    test('orders the versions the way the semantic versioning says', () {
      expect(Version.parse('1.0.0').isAtLeast(Version.parse('1.0.0')), isTrue);
      expect(
        Version.parse('1.0.0').isAtLeast(Version.parse('1.0.1')),
        isFalse,
      );
      expect(
        Version.parse('1.1.0').isAtLeast(Version.parse('1.0.9')),
        isTrue,
      );
      expect(
        Version.parse('2.0.0').isAtLeast(Version.parse('1.99.99')),
        isTrue,
      );
    });

    test('a pre-release is lower than the version it leads to', () {
      expect(
        Version.parse('1.0.0-rc.1').isLowerThan(Version.parse('1.0.0')),
        isTrue,
      );
      expect(
        Version.parse('1.0.0-rc.1').isLowerThan(Version.parse('1.0.0-rc.2')),
        isTrue,
      );
      expect(
        Version.parse('1.0.0-rc.2').isLowerThan(Version.parse('1.0.0-rc.10')),
        isTrue,
      );
    });

    test('the build part does not change the order', () {
      expect(
        Version.parse('1.0.0+a').compareTo(Version.parse('1.0.0+b')),
        0,
      );
    });

    test('the next version of a version is known', () {
      final version = Version.parse('1.2.3');

      expect(version.nextMajor.text, '2.0.0');
      expect(version.nextMinor.text, '1.3.0');
      expect(version.nextPatch.text, '1.2.4');
    });
  });

  group('ApiVersion', () {
    test('reads the version out of the package of a contract', () {
      final version = ApiVersion.of('users.v1');

      expect(version, isNotNull);
      expect(version!.name, 'users');
      expect(version.major, 1);
      expect(version.label, 'v1');
      expect(version.package, 'users.v1');
    });

    test('refuses a package without a version', () {
      expect(ApiVersion.of('users'), isNull);
      expect(ApiVersion.of('users.beta'), isNull);
      expect(ApiVersion.of(''), isNull);
    });

    test('the next major version of an API is known', () {
      expect(ApiVersion.of('users.v1')!.nextMajor.package, 'users.v2');
    });

    test('the version of the API of a contract is found', () {
      final contract = Contract(<ProtoFile>[
        ProtoFile(
          path: 'users.proto',
          package: 'users.v2',
          messages: const <Message>[],
          enums: const <EnumType>[],
          services: const <Service>[],
          imports: const <ProtoImport>[],
        ),
      ]);

      expect(apiVersionOf(contract)?.package, 'users.v2');
    });
  });
}
