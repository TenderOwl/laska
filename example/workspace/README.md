# A workspace of two services and an app

A workspace with two services that talk to each other and with the app that
carries the frontend: the first service keeps the records, the second one calls
it through the client of its contract and answers with a view of the records,
and the app serves the frontend and calls the gateway.

The files of the services are exactly the files that the command writes:

```console
$ dart run laska_cli:laska new shop
```

and the app is the file that `laska new app` writes:

```console
$ dart run laska_cli:laska new app admin --calls shop_gateway
```

so the example is the proof that the commands give a project that runs.

## The shape

```
workspace/
├── laska.yaml                     # the manifest of the workspace
├── services/
│   ├── shop/                      # the service that keeps the records
│   │   ├── api/shop.proto         # the contract
│   │   ├── lib/generated/         # the code of the contract
│   │   ├── lib/shop_service.dart  # the implementation
│   │   ├── bin/server.dart        # the entrypoint
│   │   └── test/                  # the test of the service
│   └── shop_gateway/              # the service that calls the first one
│       ├── api/shop_gateway.proto
│       ├── lib/generated/
│       ├── lib/shop_gateway_service.dart
│       ├── bin/server.dart
│       └── test/
└── apps/
    └── admin/                     # the app that carries the frontend
        ├── lib/app.dart           # the routes of the app
        ├── bin/server.dart        # the entrypoint
        ├── web/                   # the files of the frontend
        └── test/                  # the test of the app
```

The manifest tells the workspace what the participants are and what they depend
on:

```yaml
services:
  - name: shop
    entrypoint: services/shop/bin/server.dart
    port: 8080
  - name: shop_gateway
    entrypoint: services/shop_gateway/bin/server.dart
    port: 8081
    depends_on: [shop]
  - name: admin
    kind: app
    entrypoint: apps/admin/bin/server.dart
    port: 8082
    depends_on: [shop_gateway]
```

The kind of a participant tells what it is: a service of a contract answers
over the REST projection of its contract and over gRPC, and the app serves the
files of the frontend and calls the services behind it.

## Run it

```console
$ cd example/workspace
$ dart run laska_cli:laska dev
```

The command starts the participants in the order of their dependencies: the
gateway waits for the service behind it to answer, the app waits for the
gateway, and every participant gets the address of the others in its
environment.

```console
$ curl -s localhost:8081/v1/shop_gateway/u_1
$ curl -s localhost:8082/v1/shop_gateway/u_1
$ curl -s localhost:8082/
```

The call goes through the client of the contract, so it carries the timeout, the
retries and the circuit breaker of the policy of the contract, and the trace of
the request: the two services answer with one trace. The app passes the headers
of the caller to the service behind it, so the token of the session of the
browser reaches the gateway.

## The test

`test/workspace_test.dart` of the gateway starts both services in the same
process — the service that keeps the records on a real port, the gateway in
process — and checks that:

- the gateway answers with the record of the service behind it;
- a record that is not there is reported as a `404`;
- the call to the service behind belongs to the trace of the request, so the two
  services answer with one trace.

`test/app_test.dart` of the app checks that:

- the app serves the files of the frontend;
- the app forwards the call to the service behind it, and the headers of the
  caller travel with the call.
