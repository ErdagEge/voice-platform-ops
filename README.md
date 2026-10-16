# voice-platform-ops

Production-style Elixir voice call-routing service on Kubernetes: Terraform, CI/CD, observability, SLOs, DR.

## Goal

This is a portfolio project showing how a small voice/AI platform service is
built **and operated**: containerised, deployed to Kubernetes (locally on
`kind`, in the cloud on GKE via Terraform), shipped through a GitLab-style
CI/CD pipeline, observed with Prometheus/Grafana, held to SLOs, protected with
backup/DR, and hardened with chaos tests and runbooks.

The service itself, `call_router`, is a tiny Elixir HTTP API that receives an
incoming call (`from`, `to`, `intent`) and decides which queue handles it:
`sales`, `support`, or the automated `voicebot`.

## Architecture

```mermaid
flowchart LR
    caller([Caller / Telephony webhook]) -->|POST /api/calls| lb[Load Balancer / Ingress]
    lb --> svc[K8s Service]
    svc --> podInternals
    svc --> pod2[call_router pod]

    subgraph podInternals [call_router pod]
      bandit[Bandit HTTP server] --> router[Plug Router]
      router --> routing[Routing logic]
      router --> store[(ETS call store)]
      router --> metrics[Metrics registry]
    end

    prom[Prometheus] -->|scrape /metrics| svc
    prom --> graf[Grafana dashboards + SLOs]
    prom --> am[Alertmanager] --> oncall([On-call])
    k8s[Kubelet] -->|/healthz liveness, /readyz readiness| podInternals
```

Planned infrastructure: Terraform provisions a GKE cluster + networking; Helm
deploys the app; CI builds, tests, scans and pushes the image, then deploys.

## Roadmap

- [x] Elixir app (`app/`): Plug + Bandit API, health/readiness probes, JSON logs, metrics, tests
- [x] Docker: multi-stage image, non-root, small runtime (`app/Dockerfile`, `docker-compose.yml`)
- [x] Kubernetes manifests / Helm chart (probes, resources, HPA, PDB) (`deploy/helm/call-router`)
- [x] kind local cluster (one-command local environment) (`kind/cluster.yaml`)
- [ ] Terraform for GKE (VPC, cluster, node pools, Artifact Registry)
- [ ] CI/CD (GitLab-style pipeline: test, build, scan, deploy)
- [ ] Observability (Prometheus, Grafana, Alertmanager)
- [ ] SLOs (availability + latency, error budgets, burn-rate alerts)
- [ ] Backup / DR (state backup, restore drills, RTO/RPO)
- [ ] Chaos tests & runbooks (pod kills, node drain, incident playbooks)

## Running the app locally

Requirements: Elixir 1.15+ and Erlang/OTP 26+.

```bash
cd app
mix deps.get
mix test                      # run the test suite
mix format --check-formatted  # lint formatting
PORT=4000 mix run --no-halt   # start the server (PORT defaults to 4000)
```

Try it:

```bash
curl localhost:4000/healthz
curl localhost:4000/readyz
curl -X POST localhost:4000/api/calls \
  -H 'content-type: application/json' \
  -d '{"from":"+32470000001","to":"+32800000000","intent":"billing"}'
# => {"call_id":"…","queue":"support","status":"routed",…}
curl localhost:4000/api/calls/<call_id>
curl localhost:4000/metrics
```

### Endpoints

| Method | Path             | Purpose |
|--------|------------------|---------|
| GET    | `/healthz`       | Liveness: process is up |
| GET    | `/readyz`        | Readiness: able to serve traffic |
| POST   | `/api/calls`     | Route a call; body `{from, to, intent}` → 201 with decision, 422 if invalid |
| GET    | `/api/calls/:id` | Fetch a stored call (404 if unknown) |
| GET    | `/metrics`       | Prometheus text-format counters |

Intent mapping: `buy`/`pricing`/`sales` → `sales`; `help`/`support`/`billing`/`complaint` → `support`; anything else → `voicebot`.

### Configuration

| Env var     | Default | Description |
|-------------|---------|-------------|
| `PORT`      | `4000`  | HTTP listen port |
| `LOG_LEVEL` | `info` (prod) | Logger level (`debug`, `info`, `warning`, `error`) |

Logs are emitted as one JSON object per line (with `request_id`, `method`,
`path`, `status`, `duration_ms`) so they can be indexed by Loki / Cloud Logging.

## Run with Docker

```bash
docker compose up --build -d   # build the image and start a container
make smoke                     # curl /healthz, /readyz, POST /api/calls, /metrics
docker compose down            # stop and remove it
```

Or without compose: `make docker-build && make docker-run` (`make help` lists all targets).

**Image vs container.** An *image* is a read-only package: OS libraries plus
our compiled app, built once from `app/Dockerfile`. A *container* is a running
instance of that image (like a process started from a program). The same image
runs on your laptop, in CI, in `kind`, and in GKE.

**Multi-stage build.** The first stage (`hexpm/elixir`) has compilers and the
Elixir toolchain and builds a `mix release`. The second stage is a slim
Debian image that only gets the finished release, so the final image is
about 157 MB, has no build tools and no source code, and has fewer things an
attacker could use.

**Why non-root.** The app runs as UID `10001`, not root. If someone exploits
the app, they can't change the image's files or easily escalate on the host,
and it works with Kubernetes `runAsNonRoot` policies. The compose file also
makes the filesystem read-only and drops all Linux capabilities.

## Run on Kubernetes (kind)

Requirements: Docker, [kind](https://kind.sigs.k8s.io/), `kubectl`, [Helm](https://helm.sh/) 3.

```bash
make kind-up      # create a 3-node cluster (1 control-plane + 2 workers)
make kind-load    # build the image and copy it into the kind nodes
make deploy       # helm upgrade --install with values-local.yaml
make kind-smoke   # curl the app via http://localhost:8080
kubectl -n voice get pods -o wide
make kind-down    # delete the cluster
```

`make helm-lint` runs `helm lint` and checks the rendered manifests against the
Kubernetes schemas with [kubeconform](https://github.com/yannh/kubeconform).

**The concepts, in brief:**

- **Pod**: the smallest unit Kubernetes runs: one (or a few) containers
  sharing a network address. Pods are disposable; they can be killed and
  replaced at any time.
- **Deployment**: says "keep 2 copies of this pod running". If a pod or node
  dies, it creates a replacement. When you ship a new version it does a
  *rolling update*: with `maxUnavailable: 0` a new pod must be Ready before
  an old one is stopped, so there is no downtime.
- **Service**: a stable name/IP in front of the changing set of pods, which
  load-balances only to pods that are Ready. Locally it's a `NodePort`
  (30080) that kind maps to `localhost:8080`; in GKE it will sit behind a
  load balancer.
- **Probes**: the kubelet calls `/healthz` (liveness: restart the container if
  it's stuck) and `/readyz` (readiness: stop sending traffic until it's ready).
- **Graceful shutdown**: on deletion, a `preStop` sleep lets the Service stop
  routing to the pod, then the app gets SIGTERM and has
  `terminationGracePeriodSeconds` to finish in-flight requests.
- **PodDisruptionBudget**: during node drains/upgrades, keep at least 1 pod up.
- **HPA** (optional, `autoscaling.enabled`): add pods when CPU is high.
- **ConfigMap / ServiceAccount**: config as env vars (`PORT`, `LOG_LEVEL`,
  `ERL_MAX_PORTS`) and a dedicated identity for the pods.
- **Helm**: a template engine + package manager for Kubernetes YAML. The
  chart in `deploy/helm/call-router` is the template; `values.yaml` holds
  defaults and `values-local.yaml` overrides them for kind. `helm upgrade
  --install` renders and applies everything as one versioned *release* that
  can be rolled back (`helm rollback`).

> Note: calls are stored in each pod's memory, so with 2 replicas
> `GET /api/calls/:id` may hit the other pod and return 404. Shared storage
> comes in a later step.

## License

MIT - see [LICENSE](LICENSE).
