#!/usr/bin/env bash
# =============================================================================
# Demonstrates automatic rollback with `helm upgrade --atomic`.
#
# Assumes a healthy release is already deployed (scripts/deploy.sh). We then
# deploy a deliberately broken release whose readiness probe points at a path
# that returns 404, so pods never become Ready. Helm waits HELM_TIMEOUT, gives
# up, and --atomic rolls back. Thanks to maxUnavailable: 0 the old pods keep
# serving traffic the whole time.
#
# Exit code 0 = rollback demonstrated correctly.
# =============================================================================
set -euo pipefail

RELEASE="${RELEASE:-call-router}"
NAMESPACE="${NAMESPACE:-voice}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
log() { printf '[rollback-demo] %s\n' "$*"; }

rev_before=$(helm history "$RELEASE" -n "$NAMESPACE" --max 1 -o json | sed -nE 's/.*"revision":([0-9]+).*/\1/p')
path_before=$(kubectl -n "$NAMESPACE" get deploy "$RELEASE" -o jsonpath='{.spec.template.spec.containers[0].readinessProbe.httpGet.path}')
log "healthy revision: $rev_before (readiness path $path_before)"

log "deploying a BROKEN release (readiness probe -> /does-not-exist) ..."
if HELM_TIMEOUT="${HELM_TIMEOUT:-60s}" SKIP_SMOKE=true \
   HELM_EXTRA_ARGS="--set probes.readiness.path=/does-not-exist" \
   "$SCRIPT_DIR/deploy.sh"; then
  log "ERROR: broken release was accepted - rollback did NOT happen"
  exit 1
fi

helm history "$RELEASE" -n "$NAMESPACE" --max 3
status=$(helm status "$RELEASE" -n "$NAMESPACE" -o json | sed -nE 's/.*"status":"([a-z-]+)".*/\1/p' | head -1)
path_after=$(kubectl -n "$NAMESPACE" get deploy "$RELEASE" -o jsonpath='{.spec.template.spec.containers[0].readinessProbe.httpGet.path}')
log "release status after rollback: $status, readiness path: $path_after"

[ "$path_after" = "$path_before" ] || { log "ERROR: deployment still has the broken config"; exit 1; }
kubectl -n "$NAMESPACE" rollout status deploy/"$RELEASE" --timeout 120s
log "ROLLBACK DEMONSTRATED: broken release rejected, previous version still serving"
