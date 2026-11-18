# Contributing to Laska

Laska is a contract-first service framework for Dart. This page describes how
a change is made, what the checks are and what the project expects from a pull
request.

## The ground rules

- **Pure Dart.** No native toolchain, no FFI, no code generation that needs a
  binary the user has to install. A contract is compiled by the packages of
  this repository.
- **No cryptography of our own.** The cryptography comes from the packages of
  the ecosystem (`package:crypto`, `package:pointycastle`), never from a
  hand-written primitive.
- **No ORM.** The data layer is a thin `Database` over `package:postgres` and
  `package:sqlite3` with SQL migrations. The queries are written by the
  service.
- **The contract is the product.** The runtime, the clients and the documents
  are generated from it, so a change of the contract is a change of the service.
- **The English of the repository.** The code, the comments, the guides and the
  changelog are written in English; the conversations are not.

## The branches and the commits

- `main` is the branch of the releases. It is never committed to directly.
- A change lives in a branch named after what it does: `feat/contract-matrix`,
  `fix/session-cookie`, `docs/auth-guide`, `chore/toolchain`.
- The commits are written in the imperative mood and say what they do:
  `feat: add the compatibility matrix of the contracts`. The body of a commit
  explains *why* when the reason is not obvious from the diff.
- A commit is as small as it can be and it compiles: the repository is green
  after every commit, not only at the end of a branch.
- A pull request is squashed, so the history of `main` reads as a list of
  changes.

## The checks

```console
$ dart pub get
$ dart format .
$ dart run tool/check.dart
```

`tool/check.dart` runs the format, the analyzer and the tests of every package
of the workspace. The same script runs in CI on Linux, Windows and macOS.

The rules the code follows:

- `dart format .` changes nothing — the format is the format of the tool, not
  a matter of taste.
- `dart analyze .` reports nothing, not even an info. The rules of
  `package:lints/recommended.yaml` are the floor, not the ceiling.
- Every behaviour has a test. A test that cannot be written is a sign that the
  behaviour is not clear enough yet.
- A public API is documented: every public member has a doc comment that says
  what it does, not what it is.

## The changelog

`CHANGELOG.md` follows the format of Keep a Changelog. The section
`Unreleased` holds the changes that are not published yet, and every change
that a user of the framework would notice goes there — the new commands, the
new behaviour, the changes that break something.

The changes are grouped by the phase of the plan they belong to, so the
changelog reads as the history of the framework.

## The documentation

The guides live in `docs/` and they are part of the change: a new feature that
is not in the guides is not finished. The index of the guides is
`docs/README.md`, and the plan lives in `PLAN.md` at the root of the repository.

The examples of the guides are real code: they are written against the API of
the packages and they are checked by the reader. When the API changes, the
examples change with it.

## The releases

A release is a tag:

```console
$ git tag v0.1.0
$ git push --tags
```

The tag runs `.github/workflows/release.yml`, which:

1. checks that the tag matches the version of the packages;
2. builds the bundle of the command line interface for Linux, macOS and
   Windows, on x64 and on arm64, and attaches the archives to the release of
   the repository with their checksums;
3. runs the checks of the repository and publishes the packages on pub.dev —
   the secret `PUB_TOKEN` holds the token of the publisher. Without the secret
   the packages are not published and the binaries are built all the same.

The packages are published in the order of their dependencies, and the
version of the tag has to be the version of the packages. The script that
publishes them is `tool/publish.dart`:

```console
$ dart run tool/publish.dart --all --dry-run
```

The script copies the package out of the workspace, because a package of a
workspace cannot be published with `resolution: workspace`, and it refuses to
publish a tree that holds changes: the files that are published are the files
that are committed.

The version of a package is bumped before the tag, in the `pubspec.yaml` of the
four packages and in the changelog of the repository.

## The performance

The hot path of the runtime has a budget: a number of objects per request. The
rules of the budget are held by the tests of
`packages/laska_core/test/performance_test.dart` and
`packages/laska_core/test/buffers_test.dart`.

A change of the hot path is measured with the benchmark before and after:

```console
$ dart run tool/benchmark.dart
```

The numbers of the benchmark are relative — they say how much a change costs,
not how fast a service is. The guide of the performance says what the budget
is and what the benchmark covers.

## The pull request

A pull request says:

- what it changes and why;
- how it was checked — the tests that were added, the commands that were run;
- what it breaks, if it breaks something.

A pull request that changes a contract changes the generated code with it, and
the example of the repository stays in sync with its contract — the test of the
example fails otherwise.

## The security

A report of a problem in the security of the framework goes to the maintainers
before it goes to a public issue. The report says how the problem is reproduced
and what the impact is.

The authentication of the callers is part of the runtime, so a change of it is
reviewed with the same care as a change of the router: a token that is refused
must not tell an attacker what is wrong with it, and the details of a failure
must stay inside the service.
