# voice-platform-ops

[![CI](https://github.com/ErdagEge/voice-platform-ops/actions/workflows/ci.yml/badge.svg?branch=main)](https://github.com/ErdagEge/voice-platform-ops/actions/workflows/ci.yml)

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
- [x] Terraform for GKE (VPC, cluster, node pools, Artifact Registry) (`infra/terraform`, validated offline, not applied)
- [x] CI/CD (GitLab-style pipeline: test, build, scan, deploy) (`.gitlab-ci.yml`, `.github/workflows/ci.yml`, `scripts/`)
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

## Infrastructure (Terraform)

**What Terraform is.** You describe the cloud resources you want (network,
cluster, registry) in `.tf` files. `terraform plan` compares that with what
exists and shows the changes; `terraform apply` makes them. The same code
always gives the same infrastructure, changes go through code review, and
the infrastructure is documented by the code itself.

```
infra/terraform/
├── .tflint.hcl
├── modules/                 # reusable building blocks
│   ├── network/             # VPC, subnet (+ pods/services ranges), Cloud Router + NAT, deny-all firewall
│   ├── gke/                 # private GKE Standard cluster + autoscaling node pool + node service account
│   └── artifact-registry/   # Docker repo with cleanup policies + pull-only IAM
└── envs/                    # "root modules": one per environment
    ├── dev/                 # versions.tf, main.tf, variables.tf, outputs.tf,
    └── prod/                # backend.hcl.example, terraform.tfvars.example
```

**Modules** are like functions: inputs (`variables.tf`, with descriptions and
validation), resources (`main.tf`), return values (`outputs.tf`). `envs/dev`
and `envs/prod` call the same modules with different settings, so the two
environments differ only on purpose.

**What gets built (GKE design):**
- VPC-native networking: pods and Services get real VPC IPs from secondary ranges.
- **Private nodes**: no public IPs, outbound only through Cloud NAT. The
  Kubernetes API is reachable only from `master_authorized_networks`.
- **Workload Identity**: pods use Google APIs without key files.
- **Dataplane V2**: enforces Kubernetes NetworkPolicies.
- **Shielded nodes** + secure boot, COS image, legacy metadata endpoints disabled.
- A **least-privilege node service account** (logs/metrics writer, pull from
  our registry only) instead of the default Editor-level account.
- A **release channel** with auto-upgrade/auto-repair, surge upgrades
  (`max_unavailable = 0`), a weekend maintenance window.
- **Cloud Logging/Monitoring** + Managed Service for Prometheus enabled.
- A separate **autoscaling node pool** with an optional **Spot** mode.

| | dev | prod |
|---|---|---|
| Cluster | zonal (`europe-west1-b`) | regional (`europe-west1`, 3 zones) |
| Nodes | `e2-standard-2`, 1-3, **Spot** | `e2-standard-4`, 1-4 per zone (3-12), on-demand |
| Release channel | REGULAR | STABLE |
| Deletion protection | off | on |
| Image tags | mutable | immutable |

**State and backends.** Terraform records what it created in a *state* file.
Locally that's a file on disk, which is fragile and can't be shared with
teammates or CI. Here state is stored in a **GCS bucket** (`backend "gcs"`), which
is versioned (recover old state) and locked (no two applies at once). The
backend is a *partial* config: the bucket name comes from `backend.hcl`.

**Offline checks** (no cloud account needed):

```bash
make tf-check   # = tf-fmt + tf-validate (init -backend=false) + tf-lint (tflint) + tf-scan (trivy/checkov)
```

Accepted scanner findings are skipped in code with the reason written next
to them (e.g. no customer-managed encryption keys yet; Binary Authorization
planned with CI image signing).

**How it would be applied for real** (not done in this repo, and it costs money):

```bash
gcloud auth login && gcloud auth application-default login
gcloud config set project <project-id>
# one-time: state bucket (see envs/dev/backend.hcl.example)
gcloud storage buckets create gs://<project-id>-tfstate --location=europe-west1 \
  --uniform-bucket-level-access --public-access-prevention
gcloud storage buckets update gs://<project-id>-tfstate --versioning

cd infra/terraform/envs/dev
cp backend.hcl.example backend.hcl            # set bucket
cp terraform.tfvars.example terraform.tfvars  # set project_id, your IP
terraform init -backend-config=backend.hcl
terraform plan -out=tfplan                    # review!
terraform apply tfplan
$(terraform output -raw get_credentials_command)
```

In CI the same steps run with Workload Identity Federation instead of a
personal login, with `plan` on merge requests and a manual `apply` approval.

**Cost notes** (rough, list prices, europe-west1, check the
[pricing calculator](https://cloud.google.com/products/calculator)):
- GKE cluster management fee ≈ $0.10/hour (~$73/month) per cluster; the free
  tier credit covers one zonal or Autopilot cluster per billing account.
- dev: 1 Spot `e2-standard-2` ≈ $15-25/month + NAT (~$1/day + traffic) + disks.
- prod: at least 3 on-demand `e2-standard-4` ≈ $300+/month, plus regional fee,
  NAT, logging volume and load balancers.
- Flow logs, intranode visibility and log ingestion are billed by volume;
  sampling is lower in dev.
- Run `terraform destroy` on dev when it isn't in use (prod has deletion protection).

## CI/CD

Two pipelines with the same stages, both calling the same scripts in
`scripts/`, so they behave the same:

- **`.gitlab-ci.yml`**: the main one (the target platform uses GitLab):
  builds to the GitLab registry, deploys to GKE `dev` automatically and to
  `production` after a manual approval.
- **`.github/workflows/ci.yml`**: runs on every push/PR to this GitHub repo.
  Instead of GKE it deploys to a **throwaway kind cluster on the runner**, runs
  the smoke test, and proves that a broken release is rolled back.

```mermaid
flowchart LR
    subgraph lint
      L1[mix format + credo]
      L2[terraform fmt/validate + tflint]
      L3[helm lint + kubeconform]
      L4[shellcheck / hadolint / actionlint]
    end
    T[test: mix test]
    B[build: docker buildx<br/>tag = commit SHA]
    subgraph scan
      S1[trivy image<br/>fail on HIGH/CRITICAL]
      S2[trivy IaC]
      S3[SBOM CycloneDX]
      S4[cosign keyless sign]
    end
    D1[deploy-dev<br/>helm --atomic + smoke]
    G{{manual approval}}
    D2[deploy-prod<br/>helm --atomic + smoke]
    lint --> B
    T --> B --> scan --> D1 --> G --> D2
    D1 -. smoke fails .-> R[helm rollback]
    D2 -. smoke fails .-> R
```

| Script | What it does |
|---|---|
| `scripts/deploy.sh` | `helm upgrade --install --atomic --wait --timeout`, then the smoke test; `helm rollback` if the smoke test fails |
| `scripts/ci-smoke.sh` | checks `/healthz`, `/readyz`, `POST /api/calls`, 422 on bad input, `/metrics` |
| `scripts/rollback-demo.sh` | deploys a release with a broken readiness probe and checks that `--atomic` rolls it back |
| `scripts/gcp-auth.sh` | GitLab OIDC token → Google credentials via Workload Identity Federation |

Run them against kind locally: `make ci-deploy-kind` and `make rollback-demo`.

**Concepts, briefly:**
- **Stages and jobs.** Each job runs in a clean container. Stages run in order
  (lint → test → build → scan → deploy), and a failure stops the pipeline
  before anything bad reaches a cluster. `needs:` lets independent jobs start early.
- **Artifacts and caches.** *Artifacts* are files passed between jobs (the
  image tarball, the SBOM, the image digest). *Caches* (Mix deps, Docker layers,
  the Trivy DB) only make jobs faster; nothing depends on them.
- **Immutable images.** Every image is tagged with the commit SHA and deployed
  by digest, so you always know which commit is running. Rolling back means
  deploying an older SHA.
- **Supply chain.** Trivy fails the build on fixable HIGH/CRITICAL CVEs, an
  SBOM lists every package in the image, and cosign signs the image digest
  using the CI system's identity, with no signing key to store. Later, GKE
  Binary Authorization can refuse unsigned images.
- **Atomic deploys and rollback.** `--atomic --wait` means "wait until all new
  pods are Ready; if that doesn't happen in time, automatically roll back".
  Because the chart uses `maxUnavailable: 0`, the old pods keep serving the
  whole time. A release that is "Ready" but wrong is caught by the smoke test,
  which runs `helm rollback`.
- **Environments and approval.** GitLab *environments* (`dev`, `production`)
  record what is deployed where and allow one-click re-deploys. Prod is
  `when: manual` and should be a *protected environment* with required
  approvers. `resource_group` prevents two deploys to the same environment at once.
- **OIDC instead of keys.** A JSON service-account key in CI variables is
  a long-lived password: if it leaks, it works until someone notices. With
  Workload Identity Federation, GitLab issues a short-lived signed token
  per job (`id_tokens:`). Google checks it (project, branch) and returns a
  credential that expires in about an hour. The CI settings hold only resource
  names, no secrets. On GitHub, `GITHUB_TOKEN` (push to GHCR) and the OIDC
  token for cosign work the same way.

## License

MIT - see [LICENSE](LICENSE).
