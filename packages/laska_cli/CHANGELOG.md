# Changelog

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
