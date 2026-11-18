# The documentation of Laska

Laska is a contract-first service framework for Dart: one protobuf contract
produces a REST service, typed clients, an OpenAPI document and a
breaking-change check, with the observability and the resilience of the calls
built into the runtime.

| Guide | What it covers |
|---|---|
| [Getting started](getting-started.md) | Scaffold a service, run it, call it, run a workspace. |
| [Contracts](contracts.md) | The contract format, the policy of the calls, the generated code, the diff and the lint. |
| [Observability](observability.md) | Traces, metrics, logs and the health probes. |
| [Resilience](resilience.md) | Timeouts, retries, circuit breaker, bulkhead, idempotency and the outbox. |
| [Deployment](deployment.md) | The images, the Kubernetes manifests and the recipe of the continuous integration. |

The long-term design and the roadmap live in [PLAN.md](../PLAN.md) at the root
of the repository. The commands of the CLI are described by their own help:

```console
$ dart run laska_cli:laska --help
$ dart run laska_cli:laska help contract compile
```
