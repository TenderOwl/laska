# The deployment

The deployment artefacts of a workspace are written from the manifest of the
workspace, so the image of a service always matches the name and the port the
service was given.

## The images

```console
$ dart run laska_cli:laska deploy:dockerfile --manifest laska.yaml
generated: deploy/users/Dockerfile
generated: deploy/users/.dockerignore
generated: deploy/orders/Dockerfile
generated: deploy/orders/.dockerignore
```

The image is built in two steps: the Dart SDK compiles the service, and the
runtime image holds the binary and nothing else.

```dockerfile
FROM dart:3.14 AS build

WORKDIR /app

COPY pubspec.yaml pubspec.lock ./
RUN dart pub get

COPY . .
RUN dart compile exe bin/server.dart -o /app/server

FROM scratch
COPY --from=build /runtime/ /
COPY --from=build /app/server /app/server

EXPOSE 8080
ENTRYPOINT ["/app/server"]
```

The build context is the directory of the service:

```console
$ cd users
$ docker build -f ../deploy/users/Dockerfile -t laska/users:latest .
```

> A service that depends on the packages of a local workspace needs that
> workspace in the build context. A service that depends on the published
> packages needs nothing else.

The image holds the files of the service that are not code: the SQL migrations
of the service and the frontend of an app. The service runs in the directory
of the image, so the relative paths of the runtime find them.

## One binary

The image is not the only way to ship a service. The Dart SDK compiles a
service into a native binary, and the binary holds the runtime, the service and
its dependencies:

```console
$ cd users
$ dart run laska_cli:laska build
compiled: build/users_service.exe (8.4 MB)
```

The binary runs on a machine with no Dart SDK on it:

```console
$ ./build/users_service
=> Laska listening on http://0.0.0.0:8080
```

The name of the binary is the name of the package, and it is written to the
`build` directory of the package. The options name the pieces of it:

```console
$ dart run laska_cli:laska build --entrypoint bin/server.dart --out build/users
```

The files of the service are not part of the binary: the frontend of an app and
the SQL migrations of a service travel next to it, and the variables
`LASKA_WEB_ROOT` and `LASKA_MIGRATIONS_DIRECTORY` point at them.

> A compiled binary does not know the package it belongs to, so the runtime
> cannot find the files of the package by itself: it reads them against the
> directory the process runs in, or against the variables that name them.

## The cluster

```console
$ dart run laska_cli:laska deploy:k8s --manifest laska.yaml --namespace laska
generated: deploy/users.yaml
generated: deploy/orders.yaml
```

Every file holds a deployment and the service that points at it:

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: users
  namespace: laska
spec:
  replicas: 1
  selector:
    matchLabels:
      app: users
  template:
    metadata:
      labels:
        app: users
    spec:
      containers:
        - name: users
          image: laska/users:latest
          ports:
            - containerPort: 8080
---
apiVersion: v1
kind: Service
metadata:
  name: users
  namespace: laska
spec:
  selector:
    app: users
  ports:
    - port: 8080
      targetPort: 8080
```

The service of the cluster has the name of the service, so the discovery
finds it under the same name as in the workspace.

```console
$ kubectl apply -f deploy/
$ kubectl get pods
```

## The workers

`laska serve` runs the service under the supervisor: the workers share the
port, a worker that crashes is restarted, and a signal stops them all after
the running requests are finished.

```console
$ dart run laska_cli:laska serve --entrypoint bin/server.dart --workers 4 --port 8080
```

> **Platform note.** On POSIX systems the workers share the port with
> SO_REUSEPORT and the kernel balances the connections between them. Windows
> has no such option: two processes cannot listen on the same port, so the
> supervisor runs a **single worker** there and says so in the log. The
> graceful stop is weaker on Windows as well, because a signal terminates the
> worker immediately instead of letting it drain.

## The continuous integration

The recipe of the pipeline is written by the CLI:

```console
$ dart run laska_cli:laska ci:recipe --out .github/workflows/laska.yml
generated: .github/workflows/laska.yml
```

The workflow runs the format, the analyzer, the tests, the lint of the
contract and — when the two versions of the contract are given — the
comparison that fails on a breaking change:

```yaml
name: laska

on:
  push:
  pull_request:

jobs:
  check:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: dart-lang/setup-dart@v1
        with:
          sdk: stable
      - run: dart pub get
      - run: dart format --output=none --set-exit-if-changed .
      - run: dart analyze
      - run: dart test
      - run: dart run laska_cli:laska contract lint --proto api
      - run: dart run laska_cli:laska contract diff --base contracts/v1 --candidate contracts/v2
```

The same checks run on a machine with one command:

```console
$ dart run tool/check.dart
```

## The telemetry in production

The services send their traces and their metrics to the collector of the
platform, with the standard environment variables:

```console
$ export OTEL_EXPORTER_OTLP_ENDPOINT=http://otel-collector:4318
$ export OTEL_EXPORTER_OTLP_PROTOCOL=http/json
$ export OTEL_SERVICE_NAME=users
```

The probes answer the questions of the orchestrator:

```console
$ curl http://users:8080/healthz
$ curl http://users:8080/readyz
```
