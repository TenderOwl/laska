# The compatibility matrix

A contract changes over time, and the services around it change at their own
pace. The matrix of the versions of a contract answers the question a release
manager asks: **which client works against which server?**

The matrix is computed out of the contracts themselves, so it cannot drift away
from the code the services run.

## The command

```console
$ dart run laska_cli:laska contract matrix --dir contracts
```

The directory given with `--dir` holds one directory per version of the
contract:

```
contracts/
  v1/
    users.proto
  v2/
    users.proto
```

The versions may also be given one by one:

```console
$ dart run laska_cli:laska contract matrix \
    --version contracts/v1 --version contracts/v2
```

The label of a version is the name of its directory. The matrix is written as
a table:

```
client \ server  v1      v2
v1               yes     yes*
v2               yes*    yes

* the REST paths of the two versions differ.
```

The same matrix is written as Markdown with `--out`, so it can go into the
documentation of the service:

```console
$ dart run laska_cli:laska contract matrix --dir contracts --out docs/matrix.md
```

`--details` reports what every pair of versions differs in.

## How to read the matrix

The rows are the clients, the columns are the servers. A cell reads:

| Mark | Meaning |
|---|---|
| `yes` | The client works against the server. |
| `partly` | The client works, but the server lacks a part of what the client expects: the calls to the missing methods fail, the other calls keep working. |
| `no` | The client cannot work against the server: the wire itself does not match. |
| `*` | The REST paths of the two versions differ. |

The mark `*` deserves a word. The version of an API lives in the paths of its
REST projection, so the client of `/v1/users/1` cannot talk to a server that
only serves `/v2/users/1`, even when the contract itself is compatible. The
matrix keeps that apart from the other differences, because the fix is not to
change the contract but to serve both versions next to each other.

## What the matrix compares

Two contracts are matched by the simple name of their services, of their
methods and of their messages, because the package of a contract carries its
version: `users.v1` and `users.v2` hold the same service under two package
names.

The comparison of a client with a server reports:

| Difference | Effect |
|---|---|
| The server has no service the client calls. | The client cannot work. |
| The server has no method the client calls. | The client works partly. |
| The server has no message the client expects. | The client cannot work. |
| The server has no field the client expects. | The client works partly. |
| The request or the response of a method changed. | The client cannot work. |
| The type, the number or the label of a field changed. | The client cannot work. |
| The REST binding of a method changed. | The paths differ (`*`). |

A type that is written with the package it belongs to (`users.v1.User`) is
compared with its simple name (`User`), so a version bump is not read as a
change of the type.

## The matrix and the semver policy

The [policy of the versions](versioning.md) says that a breaking change goes
to the next major version of the API, and that a change that breaks nobody
stays in the version it is in. The matrix is the machine check of that policy
over more than two versions:

- a change that breaks nobody keeps the version, and every client of that
  version keeps working against the new server — the cell reads `yes`;
- a breaking change goes to the next major version, and the cell of the old
  client against the new server reads `no` or `partly`, which says that the old
  version has to be served next to the new one for as long as the old clients
  are alive.

The rule of the version is checked by `laska contract diff` for a pair of
versions, and by the matrix for the whole set of them.

## The matrix in the pipeline

The recipe of the continuous integration writes the matrix when the project
gives the directory of the versions:

```console
$ dart run laska_cli:laska ci:recipe --matrix contracts
```

The recipe then runs:

```yaml
- run: dart run laska_cli:laska contract matrix --dir contracts --out matrix.md
```

## The API of the matrix

The command is a thin layer over the API of the `laska_contracts` package, so
a project may compute the matrix itself:

```dart
import 'package:laska_contracts/laska_contracts.dart';

final matrix = buildCompatibilityMatrix(<String, Contract>{
  'v1': v1,
  'v2': v2,
});

print(matrix.table());
print(matrix.serversFor('v1'));
```

`CompatibilityReport` holds the differences of one pair, `Compatibility`
holds the verdict — `compatible`, `partial` or `incompatible` — and
`CompatibilityIssue` holds one difference with its kind.
