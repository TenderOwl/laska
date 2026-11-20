# Changelog

## Unreleased

- `laska new app <name>` writes the app of a workspace: the service that
  carries the frontend. It serves the files of the frontend, it calls the
  services behind it through the typed clients of their contracts and it comes
  with a test. The option `--calls` narrows the services it calls down, and it
  may be repeated.
- The manifest of a workspace holds the kind of a participant: `kind: app` for
  an app. A service of a contract keeps no kind, so the manifest of a workspace
  of services stays the manifest it was. A kind nobody knows is refused.
- The image of an app holds the files of the frontend, because the app serves
  them, and the variable `LASKA_WEB_ROOT` points at them.
- `laska contract sdk --lang=go` writes the SDK of a contract in Go: the
  messages of the contract, the clients of its services and the runtime they
  need. The SDK is a module of its own, and the path of the module is given
  with `--module`.

## 0.2.0

- `laska contract compile` writes the code in the style of the package it goes
  into: the command reads the version of the SDK the package declares, and the
  formatter writes the code the way `dart format` of that package would.
- The scaffolded code imports the library of the service with a `package:`
  import, which the lints of the framework accept.
- A scaffolded project depends on the version of the framework that is
  installed. The version was written in the code of the command, so every
  project it wrote depended on a version that went out of date with the next
  release.

## 0.1.0

- The first release of the command line interface: `laska new`, `laska contract
  compile`, `laska contract diff`, `laska contract lint`, `laska contract
  matrix`, `laska keys generate`, `laska upgrade`, `laska serve`, `laska dev`,
  `laska route:list`, `laska migrate:run`, `laska deploy:dockerfile`,
  `laska deploy:k8s` and `laska ci:recipe`.
- The help of every command, built from the parser, so it never drifts away
  from the options.

The history of the project lives in the
[changelog of the repository](https://github.com/tenderowl/laska/blob/main/CHANGELOG.md).
