import 'dart:io';

import 'package:laska_cli/src/cli.dart';
import 'package:laska_cli/src/scaffold.dart';
import 'package:laska_cli/src/workspace.dart';
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

void main() {
  late Directory workspace;

  setUp(() {
    workspace = Directory.systemTemp.createTempSync('laska_scaffold_test');
  });

  tearDown(() {
    if (workspace.existsSync()) {
      workspace.deleteSync(recursive: true);
    }
  });

  group('laska new service', () {
    test('writes a service that is ready to run', () async {
      final result = await _run(<String>[
        'new',
        'service',
        'users',
        '--out',
        workspace.path,
        '--manifest',
        '${workspace.path}/laska.yaml',
      ]);

      expect(result.code, 0);

      final service = Directory('${workspace.path}/users');
      expect(File('${service.path}/api/users.proto').existsSync(), isTrue);
      expect(
        File('${service.path}/lib/generated/users.pb.dart').existsSync(),
        isTrue,
      );
      expect(File('${service.path}/lib/generated/openapi.json').existsSync(),
          isTrue);
      expect(
        File('${service.path}/lib/users_service.dart').existsSync(),
        isTrue,
      );
      expect(File('${service.path}/bin/server.dart').existsSync(), isTrue);
      expect(
        File('${service.path}/test/users_service_test.dart').existsSync(),
        isTrue,
      );
      expect(File('${service.path}/pubspec.yaml').existsSync(), isTrue);
    });

    test('writes a contract with the policy of the calls', () async {
      await _run(<String>[
        'new',
        'service',
        'users',
        '--out',
        workspace.path,
        '--manifest',
        '${workspace.path}/laska.yaml',
      ]);

      final contract =
          File('${workspace.path}/users/api/users.proto').readAsStringSync();

      expect(contract, contains('package users.v1;'));
      expect(contract, contains('service UsersService {'));
      expect(contract, contains('option (laska.policy)'));
      expect(contract, contains('rpc GetUser(GetUserRequest) returns (User)'));
    });

    test('generates the code of the contract', () async {
      await _run(<String>[
        'new',
        'service',
        'users',
        '--out',
        workspace.path,
        '--manifest',
        '${workspace.path}/laska.yaml',
      ]);

      final generated =
          File('${workspace.path}/users/lib/generated/users.pb.dart')
              .readAsStringSync();

      expect(generated, contains('class User {'));
      expect(generated, contains('abstract class UsersService {'));
      expect(generated, contains('void registerUsersService('));
      expect(generated, contains('class UsersServiceClient {'));
    });

    test('adds the service to the manifest of the workspace', () async {
      await _run(<String>[
        'new',
        'service',
        'users',
        '--out',
        workspace.path,
        '--manifest',
        '${workspace.path}/laska.yaml',
      ]);

      final workspaceModel =
          readWorkspace(File('${workspace.path}/laska.yaml'));

      expect(workspaceModel.services, hasLength(1));
      expect(workspaceModel.services.single.name, 'users');
      expect(workspaceModel.services.single.port, 8080);
      expect(
        workspaceModel.services.single.entrypoint,
        'users/bin/server.dart',
      );
    });

    test('keeps the services that are already in the manifest', () async {
      File('${workspace.path}/laska.yaml').writeAsStringSync('''
services:
  - name: billing
    entrypoint: billing/bin/server.dart
    port: 8090
''');

      await _run(<String>[
        'new',
        'service',
        'users',
        '--out',
        workspace.path,
        '--manifest',
        '${workspace.path}/laska.yaml',
      ]);

      final workspaceModel =
          readWorkspace(File('${workspace.path}/laska.yaml'));

      expect(workspaceModel.services.map((service) => service.name),
          <String>['billing', 'users']);
    });

    test('fails when the manifest already holds the service', () async {
      File('${workspace.path}/laska.yaml').writeAsStringSync('''
services:
  - name: users
    entrypoint: users/bin/server.dart
    port: 8080
''');

      final result = await _run(<String>[
        'new',
        'service',
        'users',
        '--out',
        workspace.path,
        '--manifest',
        '${workspace.path}/laska.yaml',
      ]);

      expect(result.code, 65);
      expect(result.err, contains('already holds a service'));
    });

    test('fails without the name of the service', () async {
      final result = await _run(<String>['new', 'service']);

      expect(result.code, 64);
      expect(result.err, contains('Missing the name'));
    });
  });

  group('laska new', () {
    test('writes a workspace with two services', () async {
      final result = await _run(<String>[
        'new',
        'shop',
        '--out',
        workspace.path,
      ]);

      expect(result.code, 0);

      final root = Directory('${workspace.path}/shop');
      expect(File('${root.path}/laska.yaml').existsSync(), isTrue);
      expect(
        File('${root.path}/services/shop/api/shop.proto').existsSync(),
        isTrue,
      );
      expect(
        File('${root.path}/services/shop_gateway/api/shop_gateway.proto')
            .existsSync(),
        isTrue,
      );

      final workspaceModel = readWorkspace(File('${root.path}/laska.yaml'));
      expect(
        workspaceModel.services.map((service) => service.name),
        <String>['shop', 'shop_gateway'],
      );
      expect(
        workspaceModel.services.first.entrypoint,
        'services/shop/bin/server.dart',
      );
      expect(
        workspaceModel.services.last.entrypoint,
        'services/shop_gateway/bin/server.dart',
      );
      expect(workspaceModel.services.last.dependsOn, <String>['shop']);
      expect(workspaceModel.services.last.port, 8081);
    });

    test('the gateway calls the service behind it with a tracer', () async {
      await _run(<String>[
        'new',
        'shop',
        '--out',
        workspace.path,
      ]);

      final entrypoint = File(
        '${workspace.path}/shop/services/shop_gateway/bin/server.dart',
      ).readAsStringSync();

      expect(entrypoint, contains('tracer: observability.tracer'));
      expect(entrypoint, contains('ShopServiceClient('));
    });

    test('the gateway depends on the package of the service behind it',
        () async {
      await _run(<String>[
        'new',
        'shop',
        '--out',
        workspace.path,
      ]);

      final pubspec = File(
        '${workspace.path}/shop/services/shop_gateway/pubspec.yaml',
      ).readAsStringSync();

      expect(pubspec, contains('shop_service: {path: '));
    });
  });

  group('scaffoldService', () {
    test('writes the service in the directory it is given', () async {
      final result = await scaffoldService(
        'user-profiles',
        directory: Directory('${workspace.path}/profiles'),
      );

      expect(result.written, isNotEmpty);
      expect(
        File('${workspace.path}/profiles/api/user_profiles.proto').existsSync(),
        isTrue,
      );
      expect(
        File('${workspace.path}/profiles/lib/user_profiles_service.dart')
            .existsSync(),
        isTrue,
      );
    });

    test('writes the dependencies of the local workspace when it is given',
        () async {
      await scaffoldService(
        'users',
        directory: Directory('${workspace.path}/users'),
        localWorkspace: '/tmp/laska',
      );

      final pubspec =
          File('${workspace.path}/users/pubspec.yaml').readAsStringSync();

      expect(pubspec, contains('laska_core: {path: '));
      expect(pubspec, contains('laska_test: {path: '));
    });

    test('writes the published dependencies by default', () async {
      await scaffoldService(
        'users',
        directory: Directory('${workspace.path}/users'),
      );

      final pubspec =
          File('${workspace.path}/users/pubspec.yaml').readAsStringSync();

      expect(pubspec, contains('laska_core: ^${frameworkVersion()}'));
      expect(pubspec, contains('laska_test: ^${frameworkVersion()}'));
      expect(pubspec, contains('laska_contracts: ^${frameworkVersion()}'));
    });
  });

  group('laskaWorkspaceRoot', () {
    test('finds the workspace of the CLI', () async {
      final root = await laskaWorkspaceRoot();

      expect(root, isNotNull);
      expect(
        Directory('${root!.path}/packages/laska_core').existsSync(),
        isTrue,
      );
    });
  });
}
