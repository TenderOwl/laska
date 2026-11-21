# Upgrading a service

This guide says how a service moves to a new version of Laska, and how it
moves to a new version of its own API.

## Moving to a new version of the framework

1. Raise the constraint of the packages in the `pubspec.yaml` of the service:

   ```yaml
   dependencies:
     laska_core: ^0.3.0
   ```

2. Run `dart pub get` and read the [CHANGELOG](../CHANGELOG.md) of the
   version you move to. Every breaking change names the old and the new
   symbol, so the search is quick:

   ```console
   $ git grep "OldSymbolName"
   ```

3. Run the codemods of the step, if the version ships one:

   ```console
   $ dart run laska_cli:laska upgrade --from 0.2.0 --to 0.3.0
   ```

   The command answers `No codemod is needed to go from 0.2.0 to 0.3.0.`
   when the step only adds something, so it is safe to run it every time.

4. Run the format, the analyzer and the tests:

   ```console
   $ dart format .
   $ dart analyze .
   $ dart test
   ```

The command `laska upgrade` without the options of the API only runs the
codemods of the framework. The codemods of the framework rewrite the source
of the service; they never touch the contract, because the contract belongs to
the API of the service and not to the framework. The codemods are shipped with
the CLI, so they are always in step with the version of the framework that is
installed.

## Moving to a new version of the API

A breaking change of the contract needs a new version of the API, so the
callers that were not updated yet keep working. The rule and the reasons are
in [Versioning](versioning.md).

1. Write the new contract next to the old one, in the directory of the
   baseline of the continuous integration:

   ```console
   $ cp -r contracts/v1 contracts/v2
   ```

2. Change the package of the new contract and the paths of its REST
   projection:

   ```proto
   package users.v2;

   service UsersService {
     rpc GetUser(GetUserRequest) returns (User) {
       option (google.api.http) = { get: "/v2/users/{id}" };
     }
   }
   ```

3. Check that the version of the candidate follows the rule:

   ```console
   $ dart run laska_cli:laska contract diff --base contracts/v1 --candidate contracts/v2
   ```

4. Move the service to the new version:

   ```console
   $ dart run laska_cli:laska upgrade --api users --from v1 --to v2 --dry-run
   $ dart run laska_cli:laska upgrade --api users --from v1 --to v2
   ```

   The command rewrites the package of the contract, the paths of the REST
   projection and the calls of the client. It touches the `.proto` files and
   the `.dart` files of the service, and nothing else.

5. Compile the contract again and run the tests:

   ```console
   $ dart run laska_cli:laska contract compile --proto api --out lib/generated
   $ dart test
   ```

6. Serve both versions at the same time. The paths of the old version keep
   answering, so the callers are migrated one by one. When the last caller
   moved, the old version goes away.

## When a codemod is not enough

A codemod rewrites the text of the source. When a change of the framework
needs a change of the structure of the code — a new argument of a function, a
new way to build a client — the codemod cannot do it alone, and the guide of
the version says what to do.
