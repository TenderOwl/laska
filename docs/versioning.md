# The versions of Laska

Laska has two kinds of versions, and they answer two different questions:

- **The version of a package** (`laska_core`, `laska_contracts`, `laska_cli`,
  `laska_test`) tells the consumer of the package whether an update breaks his
  code.
- **The version of an API** (the `v1` of `package users.v1`) tells the caller
  of a service whether the service still speaks the same protocol.

Both follow the [semantic versioning](https://semver.org): `major.minor.patch`.

## The version of a package

| Change | The version goes up |
|---|---|
| A public API is removed, renamed or changed in a way the consumer must notice | major |
| A public API is added, or something is deprecated | minor |
| A bug is fixed and nothing else changes | patch |

Until the version `1.0.0`, the minor part may hold breaking changes: the
framework is young, and a service that wants a stable surface waits for
`1.0.0`. The rule of the minor part is written down here so the change is
never a surprise:

> Before `1.0.0`, a minor version may break the code of the consumer. Every
> breaking change is written in the [CHANGELOG](../CHANGELOG.md) with the name
> of the old and the new symbol.

From `1.0.0` on, the minor part never breaks the consumer.

## The version of an API

The version of an API lives in the name of the package of the `.proto` file:

```proto
package users.v1;
```

and in the paths of the REST projection:

```proto
option (google.api.http) = { get: "/v1/users/{id}" };
```

The two always move together: the version of the path tells the caller which
version it speaks, and the version of the package tells the compiler which
messages it may use.

### What breaks the consumers

The rules of the compatibility of a contract are the ones of protobuf, and
`laska contract diff` applies them:

| Change | Breaks the consumer |
|---|---|
| A field is removed, or its number or its type changes | yes |
| A method is removed, or its request or its response changes | yes |
| The binding of a method changes (the method or the path) | yes |
| A field, a message, an enum or a method is added | no |
| A field becomes optional or a new enum value is added | no |

### The rule of the version

> A breaking change goes to the next major version of the API. A change that
> breaks nobody stays in the version it is in.

So `users.v1` becomes `users.v2` when a field is removed, and stays
`users.v1` when a field is added. The service may keep both versions alive at
the same time: the paths of the old version keep answering, so the callers
that were not updated yet are not left behind.

The rule is not a convention but a check. `laska contract diff` compares the
contract with its baseline and tells the user when the version of the
candidate does not follow the rule:

```console
$ dart run laska_cli:laska contract diff --base contracts/v1 --candidate contracts/v2
The contract has breaking changes, so the version of the API must go from
users.v1 to users.v2, but the candidate is users.v1.
```

The command fails with the exit code `1`, so the pipeline of the continuous
integration stops before a breaking change reaches the callers.

## How a service moves to the next version

`laska upgrade` rewrites the contract, the generated code and the calls of the
service to the new version:

```console
$ dart run laska_cli:laska upgrade --api users --from v1 --to v2 --dry-run
$ dart run laska_cli:laska upgrade --api users --from v1 --to v2
```

The guide of the upgrade is in [Upgrading](upgrading.md).
