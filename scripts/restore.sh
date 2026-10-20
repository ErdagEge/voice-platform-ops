#!/usr/bin/env bash
# Restore the database from the object store into a NEW cluster, then
# (re)deploy the app and the alert rules on top of it.
#
#   scripts/restore.sh                                  # newest backup + all archived WAL
#   SOURCE=call-router-db-20261020T190000 scripts/restore.sh
#   TARGET_TIME="2026-10-20 18:30:00+00" scripts/restore.sh   # point-in-time recovery
#
# The old cluster must be gone (after a disaster it is). To restore over a
# healthy one on purpose: `make db-down` first.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export NAMESPACE="${NAMESPACE:-voice}"
log() { printf '[restore] %s %s\n' "$(date +%T)" "$*"; }

args=(--restore-from "${SOURCE:-latest}")
[ -n "${TARGET_TIME:-}" ] && args+=(--target-time "$TARGET_TIME")
"$ROOT/scripts/db-up.sh" "${args[@]}"

log "deploying the app"
IMAGE_REPO="${IMAGE_REPO:-voice-platform-ops/call_router}" IMAGE_TAG="${IMAGE_TAG:-local}" \
VALUES_FILES="${VALUES_FILES:-$ROOT/deploy/helm/call-router/values-local.yaml}" \
SMOKE_URL="${SMOKE_URL:-http://localhost:8080}" \
  "$ROOT/scripts/deploy.sh" | sed 's/^/  /'

# The alert rules live in the namespace too; skip if Prometheus Operator is absent.
if kubectl get crd prometheusrules.monitoring.coreos.com >/dev/null 2>&1; then
  for f in "$ROOT"/slo/*.rules.yml; do "$ROOT/scripts/slo-prometheusrule.sh" "$f" | kubectl apply -f - >/dev/null; done
  log "alert rules re-applied"
fi
log "restore complete"
