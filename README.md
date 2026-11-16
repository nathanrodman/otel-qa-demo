# Tiny Shop — OTel auto-injection QA app

A deliberately **uninstrumented** 3-language microservice app for QA-ing a Helm-based flow
that instruments a Kubernetes cluster and auto-injects OpenTelemetry SDKs.

```
loadgen ──> frontend (Node.js 22) ──> orders (Python 3.12 / Flask) ──> inventory (Java 21 / Spring Boot)
                                            │
                                            └──> redis
```

| Service   | Language / framework | What auto-instrumentation should produce              |
|-----------|----------------------|-------------------------------------------------------|
| frontend  | Node.js, core `http` | HTTP server spans + outbound HTTP client spans        |
| orders    | Python, Flask        | Flask server spans, `requests` client spans, Redis spans |
| inventory | Java, Spring Boot    | Spring MVC server spans, JVM metrics, logback logs    |
| redis     | Redis 7 (3rd party)  | (dependency only — appears as a downstream DB)        |
| loadgen   | curl loop            | ~1–2 req/s of steady traffic                          |

Built-in behavior so the telemetry is interesting:
- inventory: 5–40 ms latency, ~5% slow outliers (300–800 ms), ~3% simulated 500s
- `sku-unknown` → 404 from inventory; `sku-durian` runs out of stock periodically → 409
- Images are Debian/glibc-based (not Alpine) so the default OTel operator injection images work.

There are **no** OTel SDKs, `OTEL_*` env vars, or `instrumentation.opentelemetry.io/*`
annotations in this repo — that's what the flow under test is supposed to add.

## Prereqs

`docker`, `k3d`, `kubectl`, `helm`, `make`.

## Usage

```sh
make up            # create k3d cluster "otel-qa", build + import images, deploy to ns tiny-shop
make smoke         # end-to-end request from inside the cluster
make status        # pods, init containers, and any injected OTEL_* / agent env vars
make port-forward  # http://localhost:8080
make logs
make down          # delete the cluster
```

`make up` switches your current kube context to `k3d-otel-qa`. Note that `make down` removes that
context and k3d falls back to another one (possibly a real cluster) — check
`kubectl config current-context` before running helm. To be safe, target it explicitly:

```sh
kubectl --context k3d-otel-qa -n tiny-shop get pods
helm --kube-context k3d-otel-qa ...
```

## QA flow

1. `make up && make smoke` — baseline: app works, `make status` shows no injection.
2. Run the new Helm install command against `--kube-context k3d-otel-qa`.
3. `make restart` — admission webhooks only mutate pods at creation time, so existing pods
   need restarting (skip this if the flow is supposed to restart workloads itself — that's
   worth checking).
4. `make status` — expect an injected init container (e.g. `opentelemetry-auto-instrumentation-*`)
   and env vars like `JAVA_TOOL_OPTIONS`, `NODE_OPTIONS`, `PYTHONPATH`, `OTEL_EXPORTER_OTLP_ENDPOINT`,
   `OTEL_SERVICE_NAME` on frontend / orders / inventory.
5. In Grafana: confirm traces span frontend → orders → inventory (+ redis), service names match
   the deployments, k8s resource attributes (namespace/pod/deployment) are attached, and the
   simulated errors/latency show up.

Things worth checking while QA-ing:
- Are all three languages detected and injected, or only some?
- Does redis (a non-app workload) get left alone?
- Does the loadgen (curl, no supported runtime) get left alone without breaking?
- Does `kube-system` / the instrumentation's own namespace get excluded?
- Uninstall path: after `helm uninstall` + `make restart`, do pods come back clean?
