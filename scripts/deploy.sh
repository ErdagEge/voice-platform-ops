#!/usr/bin/env bash
# =============================================================================
# Deploy the call-router Helm chart, smoke-test it, roll back on failure.
# Shared by GitLab CI (GKE), GitHub Actions (kind) and local use.
#
# Required env:
#   IMAGE_REPO   e.g. europe-west1-docker.pkg.dev/proj/voice-platform-dev/call_router
#   IMAGE_TAG    e.g. the git commit SHA
# Optional env (defaults in brackets):
#   RELEASE [call-router]  NAMESPACE [voice]  CHART [deploy/helm/call-router]
#   VALUES_FILES ["" - space-separated extra -f files]
#   HELM_TIMEOUT [5m]      HELM_EXTRA_ARGS [""]
#   SMOKE_URL   if set, smoke-test this URL; otherwise port-forward the Service
#   SKIP_SMOKE  [false]
#
# Safety net, in two layers:
#   1. `helm upgrade --atomic --wait`: if pods don't become Ready (failing
#      readiness probe, crash loop, bad image) within HELM_TIMEOUT, Helm
#      automatically rolls back to the previous release.
#   2. If Helm succeeds but the smoke test fails (app is "Ready" but broken),
#      we run `helm rollback` ourselves and fail the job.
# =============================================================================
set -euo pipefail

: "${IMAGE_REPO:?IMAGE_REPO is required}"
: "${IMAGE_TAG:?IMAGE_TAG is required}"
RELEASE="${RELEASE:-call-router}"
NAMESPACE="${NAMESPACE:-voice}"
CHART="${CHART:-deploy/helm/call-router}"
HELM_TIMEOUT="${HELM_TIMEOUT:-5m}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

log() { printf '[deploy] %s\n' "$*"; }

values_args=()
for f in ${VALUES_FILES:-}; do values_args+=(-f "$f"); done

# Remember the current revision so we know whether a rollback target exists.
prev_rev=$(helm history "$RELEASE" -n "$NAMESPACE" --max 1 -o json 2>/dev/null \
  | sed -nE 's/.*"revision":([0-9]+).*/\1/p' || true)
log "release=$RELEASE ns=$NAMESPACE image=$IMAGE_REPO:$IMAGE_TAG previous_revision=${prev_rev:-none}"

# shellcheck disable=SC2086  # HELM_EXTRA_ARGS is intentionally word-split
if ! helm upgrade --install "$RELEASE" "$CHART" \
  --namespace "$NAMESPACE" --create-namespace \
  "${values_args[@]}" \
  --set image.repository="$IMAGE_REPO" \
  --set image.tag="$IMAGE_TAG" \
  --atomic --wait --timeout "$HELM_TIMEOUT" \
  ${HELM_EXTRA_ARGS:-}; then
  log "helm upgrade FAILED - --atomic has rolled back to the previous release"
  helm history "$RELEASE" -n "$NAMESPACE" --max 5 || true
  exit 1
fi
log "helm upgrade succeeded"

if [ "${SKIP_SMOKE:-false}" = "true" ]; then exit 0; fi

# Smoke test: use SMOKE_URL if given (e.g. kind NodePort), otherwise open a
# temporary tunnel to the Service with kubectl port-forward.
pf_pid=""
# shellcheck disable=SC2317,SC2329  # invoked via trap
cleanup() { if [ -n "$pf_pid" ]; then kill "$pf_pid" 2>/dev/null || true; fi; }
trap cleanup EXIT

url="${SMOKE_URL:-}"
if [ -z "$url" ]; then
  local_port="${SMOKE_LOCAL_PORT:-18080}"
  kubectl -n "$NAMESPACE" port-forward "svc/$RELEASE" "$local_port:80" >/tmp/port-forward.log 2>&1 &
  pf_pid=$!
  url="http://127.0.0.1:$local_port"
fi

if BASE_URL="$url" "$SCRIPT_DIR/ci-smoke.sh"; then
  log "smoke test passed - deploy complete"
  exit 0
fi

log "smoke test FAILED"
if [ -n "${prev_rev:-}" ]; then
  log "rolling back to the previous revision"
  helm rollback "$RELEASE" -n "$NAMESPACE" --wait --timeout "$HELM_TIMEOUT"
  helm history "$RELEASE" -n "$NAMESPACE" --max 5 || true
else
  log "no previous revision to roll back to (first install)"
fi
exit 1
