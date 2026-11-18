# laska_cli

The command line interface of [Laska](https://github.com/tenderowl/laska), a
contract-first service framework for Dart.

```console
$ laska new shop
$ laska contract compile --proto api --out lib/generated
$ laska contract diff --base contracts/v1 --candidate contracts/v2
$ laska dev
```

## The installation

From pub.dev, with the Dart SDK on the machine:

```console
$ dart pub global activate laska_cli
```

Without the Dart SDK, from the [release](https://github.com/tenderowl/laska/releases)
of the project:

```console
$ curl -fsSL https://raw.githubusercontent.com/tenderowl/laska/main/tool/install.sh | sh
```

## What it holds

- `laska new` — a workspace with two services, or a service inside a workspace.
- `laska contract compile` — the Dart code and the OpenAPI document of a
  contract.
- `laska contract diff` — the breaking changes of a contract, for the pipeline.
- `laska contract lint` — the rules of the framework, checked on the contract.
- `laska contract matrix` — which client works against which server.
- `laska keys generate` — the keys that sign the tokens of the service.
- `laska upgrade` — the move to a new version of the framework or of the API.
- `laska dev` — every service of the workspace, in the order of their
  dependencies.
- `laska serve`, `laska route:list`, `laska migrate:run`, `laska deploy:*`,
  `laska ci:recipe`.

Every command has a help of its own: `laska help <command>`.

## The documentation

The guide of the command line interface lives in
[docs/getting-started.md](https://github.com/tenderowl/laska/blob/main/docs/getting-started.md).

## The licence

MIT — see [LICENSE](LICENSE).
