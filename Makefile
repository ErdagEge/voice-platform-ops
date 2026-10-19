# Shortcuts. Run `make help` to list them.
IMAGE ?= voice-platform-ops/call_router:local
PORT  ?= 4000

.PHONY: help deps test fmt run docker-build docker-run up down smoke

help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?## ' $(MAKEFILE_LIST) | awk -F':.*?## ' '{printf "  %-14s %s\n", $$1, $$2}'

deps: ## Fetch Elixir deps
	cd app && mix deps.get

test: deps ## Run format check + tests
	cd app && mix format --check-formatted && mix test

run: deps ## Run the app locally without Docker
	cd app && PORT=$(PORT) mix run --no-halt

docker-build: ## Build the Docker image
	docker build -t $(IMAGE) app

docker-run: ## Run the image in the foreground (Ctrl+C to stop)
	docker run --rm -it -p $(PORT):4000 $(IMAGE)

up: ## Start with docker compose (background)
	docker compose up --build -d

down: ## Stop docker compose
	docker compose down

smoke: ## Hit the main endpoints of a running instance
	curl -fsS localhost:$(PORT)/healthz && echo
	curl -fsS localhost:$(PORT)/readyz && echo
	curl -fsS -X POST localhost:$(PORT)/api/calls -H 'content-type: application/json' \
	  -d '{"from":"+32470000001","to":"+32800000000","intent":"buy"}' && echo
	curl -fsS localhost:$(PORT)/metrics

# ---- Kubernetes (kind) ----------------------------------------------------
CLUSTER ?= voice-platform
RELEASE ?= call-router
NS      ?= voice
CHART   := deploy/helm/call-router

.PHONY: kind-up kind-load deploy kind-smoke kind-down helm-lint

kind-up: ## Create the local kind cluster (1 control-plane + 2 workers)
	kind get clusters | grep -qx $(CLUSTER) || kind create cluster --config kind/cluster.yaml

kind-load: docker-build ## Build the image and load it into kind nodes
	kind load docker-image $(IMAGE) --name $(CLUSTER)

deploy: ## helm upgrade --install into the kind cluster
	helm upgrade --install $(RELEASE) $(CHART) -n $(NS) --create-namespace \
	  -f $(CHART)/values-local.yaml --wait --timeout 3m

helm-lint: ## Lint the chart and validate rendered manifests with kubeconform
	helm lint $(CHART) -f $(CHART)/values-local.yaml
	helm template $(RELEASE) $(CHART) -f $(CHART)/values-local.yaml --set autoscaling.enabled=true \
	  --api-versions monitoring.coreos.com/v1/ServiceMonitor \
	  | kubeconform -strict -summary -schema-location default -schema-location '$(CRD_SCHEMAS)' -

kind-smoke: ## Smoke-test the app through localhost:8080
	./scripts/kind-smoke.sh

kind-down: ## Delete the kind cluster
	kind delete cluster --name $(CLUSTER)

# ---- Terraform (offline checks only - nothing here talks to GCP) ----------
TF_DIR  := infra/terraform
TF_ENVS := dev prod

.PHONY: tf-fmt tf-validate tf-lint tf-scan tf-check

tf-fmt: ## Check Terraform formatting (run `terraform fmt -recursive` to fix)
	terraform fmt -check -recursive $(TF_DIR)

tf-validate: ## terraform init (no backend) + validate for each env
	@for e in $(TF_ENVS); do \
	  echo "== $$e"; \
	  terraform -chdir=$(TF_DIR)/envs/$$e init -backend=false -input=false >/dev/null && \
	  terraform -chdir=$(TF_DIR)/envs/$$e validate || exit 1; \
	done

tf-lint: ## tflint (with the Google ruleset) across all modules/envs
	cd $(TF_DIR) && tflint --init && tflint --recursive --config "$$PWD/.tflint.hcl"

tf-scan: ## IaC security scan with trivy (and checkov if installed)
	trivy config --exit-code 1 $(TF_DIR)
	@if command -v checkov >/dev/null; then checkov -d $(TF_DIR) --framework terraform --compact --quiet; fi

tf-check: tf-fmt tf-validate tf-lint tf-scan ## All Terraform checks

# ---- CI/CD helpers (same scripts the pipelines run) ------------------------
.PHONY: ci-deploy-kind rollback-demo ci-lint

ci-deploy-kind: ## Deploy to kind via scripts/deploy.sh (atomic + smoke + rollback)
	IMAGE_REPO=voice-platform-ops/call_router IMAGE_TAG=local \
	VALUES_FILES=$(CHART)/values-local.yaml SMOKE_URL=http://localhost:8080 \
	./scripts/deploy.sh

rollback-demo: ## Deploy a broken release to kind and show --atomic rolling it back
	IMAGE_REPO=voice-platform-ops/call_router IMAGE_TAG=local \
	VALUES_FILES=$(CHART)/values-local.yaml HELM_TIMEOUT=60s \
	./scripts/rollback-demo.sh

ci-lint: ## Lint the CI definitions (actionlint + shellcheck)
	actionlint
	shellcheck scripts/*.sh

# ---- Observability (local kind, all OSS) -----------------------------------
OBS_NS  := monitoring
OBS_DIR := deploy/observability
KPS_VERSION   := 92.10.1
TEMPO_VERSION := 3.2.0
LOKI_VERSION  := 18.17.1
ALLOY_VERSION := 1.13.1
CRD_SCHEMAS := https://raw.githubusercontent.com/datreeio/CRDs-catalog/main/{{.Group}}/{{.ResourceKind}}_{{.ResourceAPIVersion}}.json

.PHONY: obs-repos obs-up obs-down grafana prometheus alertmanager slo-check slo-test slo-apply load

obs-repos:
	helm repo add prometheus-community https://prometheus-community.github.io/helm-charts --force-update
	helm repo add grafana https://grafana.github.io/helm-charts --force-update
	helm repo add grafana-community https://grafana-community.github.io/helm-charts --force-update
	helm repo update

obs-up: obs-repos ## Install Prometheus/Alertmanager/Grafana, Tempo, Loki, Alloy into kind + SLO rules
	helm upgrade --install kps prometheus-community/kube-prometheus-stack --version $(KPS_VERSION) \
	  -n $(OBS_NS) --create-namespace -f $(OBS_DIR)/kube-prometheus-stack.values.yaml --wait --timeout 10m
	helm upgrade --install tempo grafana-community/tempo --version $(TEMPO_VERSION) \
	  -n $(OBS_NS) -f $(OBS_DIR)/tempo.values.yaml --wait --timeout 5m
	helm upgrade --install loki grafana-community/loki --version $(LOKI_VERSION) \
	  -n $(OBS_NS) -f $(OBS_DIR)/loki.values.yaml --wait --timeout 5m
	helm upgrade --install alloy grafana/alloy --version $(ALLOY_VERSION) \
	  -n $(OBS_NS) -f $(OBS_DIR)/alloy.values.yaml --wait --timeout 5m
	$(MAKE) slo-apply

obs-down: ## Remove the observability stack
	-helm uninstall alloy loki tempo kps -n $(OBS_NS)
	-kubectl delete prometheusrule call-router-slo -n $(NS)

grafana: ## Grafana on http://localhost:3000 (admin/admin)
	kubectl -n $(OBS_NS) port-forward svc/kps-grafana 3000:80

prometheus: ## Prometheus on http://localhost:9090
	kubectl -n $(OBS_NS) port-forward svc/kps-prometheus 9090:9090

alertmanager: ## Alertmanager on http://localhost:9093
	kubectl -n $(OBS_NS) port-forward svc/kps-alertmanager 9093:9093

slo-check: ## promtool: validate SLO recording/alerting rules
	promtool check rules slo/call-router-slo.rules.yml

slo-test: ## promtool: run SLO rule unit tests
	promtool test rules slo/tests/*.test.yml

slo-apply: ## Apply SLO rules to the cluster as a PrometheusRule
	./scripts/slo-prometheusrule.sh | kubectl apply -f -

load: ## Generate traffic against kind (DURATION=120 seconds)
	./scripts/load.sh
