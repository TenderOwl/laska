import 'dart:convert';
import 'dart:io';

import 'package:laska_cli/src/cli.dart';
import 'package:test/test.dart';

/// The result of one run of the command line interface.
typedef CliResult = ({int code, String out, String err});

/// Runs the command line interface in process.
Future<CliResult> _run(List<String> arguments) async {
  final out = StringBuffer();
  final err = StringBuffer();
  final code = await runCli(arguments, out: out, err: err);
  return (code: code, out: out.toString(), err: err.toString());
}

/// The document of the key set in the [directory].
Map<String, dynamic> _keySet(String directory) =>
    jsonDecode(File('$directory/jwks.json').readAsStringSync())
        as Map<String, dynamic>;

void main() {
  late Directory workspace;

  setUp(() {
    workspace = Directory.systemTemp.createTempSync('laska_keys_test');
  });

  tearDown(() {
    workspace.deleteSync(recursive: true);
  });

  group('laska keys generate', () {
    test('writes the private key and the key set of the service', () async {
      final result = await _run(<String>[
        'keys',
        'generate',
        '--alg',
        'es256',
        '--out',
        workspace.path,
      ]);

      expect(result.code, 0, reason: result.err);
      expect(File('${workspace.path}/jwks.json').existsSync(), isTrue);

      final keySet = _keySet(workspace.path);
      final keys = keySet['keys'] as List<dynamic>;
      expect(keys, hasLength(1));

      final key = keys.first as Map<String, dynamic>;
      expect(key['kty'], 'EC');
      expect(key['alg'], 'ES256');
      expect(key.containsKey('d'), isFalse);

      final privateFiles = workspace
          .listSync()
          .whereType<File>()
          .where((file) => file.path.endsWith('.private.json'))
          .toList();
      expect(privateFiles, hasLength(1));

      final privateKey = jsonDecode(privateFiles.first.readAsStringSync())
          as Map<String, dynamic>;
      expect(privateKey.containsKey('d'), isTrue);
    });

    test('the key set of the service holds the key of RSA', () async {
      final result = await _run(<String>[
        'keys',
        'generate',
        '--alg',
        'rs256',
        '--bits',
        '1024',
        '--out',
        workspace.path,
      ]);

      expect(result.code, 0, reason: result.err);

      final key = (_keySet(workspace.path)['keys'] as List<dynamic>).first
          as Map<String, dynamic>;
      expect(key['kty'], 'RSA');
      expect(key['n'], isNotEmpty);
    });

    test('a key with the same id replaces the old one in the key set',
        () async {
      for (var run = 0; run < 2; run++) {
        final result = await _run(<String>[
          'keys',
          'generate',
          '--alg',
          'es256',
          '--kid',
          'auth-1',
          '--out',
          workspace.path,
        ]);
        expect(result.code, 0, reason: result.err);
      }

      final keys = _keySet(workspace.path)['keys'] as List<dynamic>;
      expect(keys, hasLength(1));
      expect((keys.first as Map<String, dynamic>)['kid'], 'auth-1');
    });

    test('refuses an algorithm it does not know', () async {
      final result = await _run(<String>[
        'keys',
        'generate',
        '--alg',
        'none',
        '--out',
        workspace.path,
      ]);

      expect(result.code, 64);
      expect(result.err, contains('none'));
    });

    test('refuses a key of RSA that is too small', () async {
      final result = await _run(<String>[
        'keys',
        'generate',
        '--alg',
        'rs256',
        '--bits',
        '512',
        '--out',
        workspace.path,
      ]);

      expect(result.code, 64);
      expect(result.err, contains('1024'));
    });
  });
}
