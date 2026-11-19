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
| [Authentication](auth.md) | The tokens, the JWKS, the API keys, the sessions and the limits of the callers. |
| [Deployment](deployment.md) | The images, the Kubernetes manifests and the recipe of the continuous integration. |
| [Versioning](versioning.md) | The semver policy of the packages and of the APIs, and how a breaking change is detected. |
| [Upgrading](upgrading.md) | How a service moves to a new version of the framework or of its own API. |
| [Compatibility](compatibility.md) | The matrix of the versions of a contract: which client works against which server. |
| [Performance](performance.md) | The hot path of the runtime, its budget and the benchmark. |
| [Examples](examples.md) | The examples of the repository: the vertical slice, the authentication, the data layer and the workspace of two services. |

The long-term design and the roadmap live in [PLAN.md](../PLAN.md) at the root
of the repository. The commands of the CLI are described by their own help:

```console
$ dart run laska_cli:laska --help
$ dart run laska_cli:laska help contract compile
```
