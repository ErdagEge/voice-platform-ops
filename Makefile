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
