import 'dart:io';

import 'package:laska_cli/src/build.dart';
import 'package:laska_cli/src/cli.dart';
import 'package:test/test.dart';

/// The tests of the compilation start real processes, so they need more time
/// than the default timeout of thirty seconds.
const Timeout _timeout = Timeout(Duration(minutes: 3));

/// The result of one run of the command line interface.
typedef CliResult = ({int code, String out, String err});

/// Runs the command line interface in process.
Future<CliResult> _run(List<String> arguments) async {
  final out = StringBuffer();
  final err = StringBuffer();
  final code = await runCli(arguments, out: out, err: err);
  return (code: code, out: out.toString(), err: err.toString());
}

/// Writes a package of a service in the directory [path].
void _writeService(Directory path, {String entrypoint = 'bin/server.dart'}) {
  Directory('${path.path}/bin').createSync(recursive: true);
  File('${path.path}/pubspec.yaml').writeAsStringSync('''
name: users_service
environment:
  sdk: ^3.6.0
''');
  File('${path.path}/$entrypoint').writeAsStringSync('''
import 'dart:io';

void main() {
  stdout.writeln('laska');
}
''');
}

void main() {
  late Directory package;

  setUp(() {
    package = Directory.systemTemp.createTempSync('laska_build_test');
  });

  tearDown(() {
    if (package.existsSync()) {
      package.deleteSync(recursive: true);
    }
  });

  group('the plan of the compilation', () {
    test('takes the entrypoint of the service', () {
      _writeService(package);

      final plan = planOfBuild(package);

      expect(plan.entrypoint, endsWith('bin/server.dart'));
      expect(plan.workingDirectory, package.absolute.path);
    });

    test('takes the name of the package for the binary', () {
      _writeService(package);

      final plan = planOfBuild(package);

      expect(
        plan.output,
        endsWith(
            '${_separator()}build${_separator()}users_service${_suffix()}'),
      );
    });

    test('takes the output that is given', () {
      _writeService(package);

      final plan = planOfBuild(package, output: 'build/users');

      expect(plan.output, endsWith('${_separator()}build${_separator()}users'));
    });

    test('fails when the package holds no entrypoint', () {
      expect(
        () => planOfBuild(package),
        throwsA(
          isA<BuildException>().having(
            (error) => error.message,
            'message',
            contains('No entrypoint found'),
          ),
        ),
      );
    });

    test('fails when the entrypoint does not exist', () {
      _writeService(package);

      expect(
        () => planOfBuild(package, entrypoint: 'bin/missing.dart'),
        throwsA(
          isA<BuildException>().having(
            (error) => error.message,
            'message',
            contains('does not exist'),
          ),
        ),
      );
    });
  });

  group('laska build', () {
    test('compiles the service into a single binary', () async {
      _writeService(package);

      final result = await _run(<String>[
        'build',
        '--path',
        package.path,
      ]);

      expect(result.code, 0, reason: result.err);

      final binary = File('${package.path}/build/users_service${_suffix()}');
      expect(binary.existsSync(), isTrue);
      expect(result.out, contains('compiled:'));
      expect(result.out, contains('users_service'));
    }, timeout: _timeout);

    test('the binary runs alone', () async {
      _writeService(package);

      final result = await _run(<String>['build', '--path', package.path]);
      expect(result.code, 0, reason: result.err);

      final binary = File('${package.path}/build/users_service${_suffix()}');
      final run = await Process.run(binary.path, const <String>[]);

      expect(run.exitCode, 0);
      expect(run.stdout.toString().trim(), 'laska');
    }, timeout: _timeout);

    test('fails when the package holds no entrypoint', () async {
      final result = await _run(<String>['build', '--path', package.path]);

      expect(result.code, 66);
      expect(result.err, contains('No entrypoint found'));
    });

    test('fails when the service does not compile', () async {
      _writeService(package);
      File('${package.path}/bin/server.dart').writeAsStringSync(
        'void main() { this is not Dart; }',
      );

      final result = await _run(<String>['build', '--path', package.path]);

      expect(result.code, 65);
      expect(result.err, isNotEmpty);
    }, timeout: _timeout);
  });

  group('the Dart SDK', () {
    test('is found', () {
      expect(findDartExecutable(), isNotNull);
    });
  });
}

/// The suffix of the binary of the platform.
String _suffix() => Platform.isWindows ? '.exe' : '';

/// The separator of the paths of the platform.
String _separator() => Platform.pathSeparator;
