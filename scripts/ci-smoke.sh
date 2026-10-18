#!/usr/bin/env bash
# =============================================================================
# Post-deploy smoke test, shared by GitLab CI, GitHub Actions and local runs.
#
#   BASE_URL=http://localhost:8080 scripts/ci-smoke.sh
#
# Exits non-zero if any check fails, so a pipeline (or deploy.sh) can react,
# e.g. by rolling the release back.
# =============================================================================
set -euo pipefail

BASE_URL="${BASE_URL:-${1:-http://localhost:8080}}"
RETRIES="${SMOKE_RETRIES:-20}"   # wait up to RETRIES*2s for the first answer

log() { printf '[smoke] %s\n' "$*"; }
fail() { printf '[smoke] FAIL: %s\n' "$*" >&2; exit 1; }

# 1. Wait until the endpoint answers at all (Service/port-forward warming up).
for i in $(seq "$RETRIES"); do
  if curl -fsS -m 3 -o /dev/null "$BASE_URL/healthz"; then break; fi
  [ "$i" -eq "$RETRIES" ] && fail "$BASE_URL/healthz not reachable"
  sleep 2
done
log "healthz ok"

# 2. Readiness must say ready.
curl -fsS -m 3 "$BASE_URL/readyz" | grep -q '"ready"' || fail "readyz not ready"
log "readyz ok"

# 3. Business endpoint: route a call and check the decision.
resp=$(curl -fsS -m 5 -X POST "$BASE_URL/api/calls" \
  -H 'content-type: application/json' \
  -d '{"from":"+32470000001","to":"+32800000000","intent":"billing"}') || fail "POST /api/calls"
echo "$resp" | grep -q '"queue":"support"' || fail "unexpected routing decision: $resp"
log "POST /api/calls ok -> $resp"

# 4. Validation errors return 422 (bad input must not be a 500).
code=$(curl -s -m 5 -o /dev/null -w '%{http_code}' -X POST "$BASE_URL/api/calls" \
  -H 'content-type: application/json' -d '{}')
[ "$code" = "422" ] || fail "expected 422 for invalid body, got $code"
log "validation ok"

# 5. Prometheus metrics are exposed. Counters live in each pod's memory and
# the Service load-balances, so this request may hit a pod that never saw our
# POST. http_requests_total exists on every pod (kubelet probes are counted),
# so we check that instead of call_router_calls_routed_total.
curl -fsS -m 3 "$BASE_URL/metrics" | grep -q '^http_requests_total' || fail "metrics missing"
log "metrics ok"

log "ALL CHECKS PASSED"
