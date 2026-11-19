import 'dart:convert';
import 'dart:io';

import 'package:contract_slice_example/generated/users.pb.dart';
import 'package:contract_slice_example/service.dart';
import 'package:laska_core/laska_core.dart';
import 'package:test/test.dart';

/// The test starts the service and runs the program of Go, so it needs more
/// time than the default timeout of thirty seconds.
const Timeout _timeout = Timeout(Duration(minutes: 3));

/// Finds the program [name] on the path of the system.
///
/// Returns `null` when the program is not installed.
String? _executableOnPath(String name) {
  final path = Platform.environment['PATH'] ?? '';
  final separator = Platform.isWindows ? ';' : ':';
  final extensions = Platform.isWindows
      ? const <String>['.exe', '.bat', '.cmd', '']
      : const <String>[''];

  for (final directory in path.split(separator)) {
    final trimmed = directory.trim();
    if (trimmed.isEmpty) {
      continue;
    }
    for (final extension in extensions) {
      final candidate =
          File('$trimmed${Platform.pathSeparator}$name$extension');
      if (candidate.existsSync()) {
        return candidate.path;
      }
    }
  }
  return null;
}

void main() {
  test(
    'the client of Go calls the service over gRPC',
    () async {
      final go = _executableOnPath('go');
      if (go == null) {
        markTestSkipped('the toolchain of Go is not installed');
        return;
      }

      final app = Laska();
      registerUsersService(app, UsersServiceImpl());

      final server = await serveGrpc(app, address: '127.0.0.1', port: 0);
      addTearDown(server.stop);

      final result = await Process.run(
        go,
        <String>['run', './cmd/e2e', '127.0.0.1:${server.port}'],
        workingDirectory: '${Directory.current.path}/go',
      );

      expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');

      final answer =
          jsonDecode(result.stdout as String) as Map<String, dynamic>;

      expect(answer['id'], 'u_1');
      expect(answer['email'], 'ada@example.com');
      expect(answer['displayName'], 'Ada Lovelace');
      expect(answer['role'], 'USER_ROLE_ADMIN');
      expect(answer['tags'], <String>['founder', 'mathematician']);
      expect(answer['createdAt'], 1767225600);
      expect(answer['users'], 1);
      expect(answer['missingCode'], 5);
    },
    timeout: _timeout,
  );
}
