# A workspace of two services

A workspace with two services that talk to each other: the first one keeps the
records, the second one calls it through the client of its contract and answers
with a view of the records.

The files of the example are exactly the files that the command writes:

```console
$ dart run laska_cli:laska new shop
```

so the example is the proof that the command gives a project that runs.

## The shape

```
workspace/
├── laska.yaml                     # the manifest of the workspace
└── services/
    ├── shop/                      # the service that keeps the records
    │   ├── api/shop.proto         # the contract
    │   ├── lib/generated/         # the code of the contract
    │   ├── lib/shop_service.dart  # the implementation
    │   ├── bin/server.dart        # the entrypoint
    │   └── test/                  # the test of the service
    └── shop_gateway/              # the service that calls the first one
        ├── api/shop_gateway.proto
        ├── lib/generated/
        ├── lib/shop_gateway_service.dart
        ├── bin/server.dart
        └── test/
```

The manifest tells the workspace what the services are and what they depend on:

```yaml
services:
  - name: shop
    entrypoint: services/shop/bin/server.dart
    port: 8080
  - name: shop_gateway
    entrypoint: services/shop_gateway/bin/server.dart
    port: 8081
    depends_on: [shop]
```

## Run it

```console
$ cd example/workspace
$ dart run laska_cli:laska dev
```

The command starts the services in the order of their dependencies: the gateway
waits for the service behind it to answer, and every service gets the address
of the others in its environment.

```console
$ curl -s localhost:8081/v1/shop_gateway/u_1
```

The call goes through the client of the contract, so it carries the timeout, the
retries and the circuit breaker of the policy of the contract, and the trace of
the request: the two services answer with one trace.

## The test

`test/workspace_test.dart` of the gateway starts both services in the same
process — the service that keeps the records on a real port, the gateway in
process — and checks that:

- the gateway answers with the record of the service behind it;
- a record that is not there is reported as a `404`;
- the call to the service behind belongs to the trace of the request, so the two
  services answer with one trace.
