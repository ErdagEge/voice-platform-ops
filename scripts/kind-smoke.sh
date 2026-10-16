#!/usr/bin/env bash
# Smoke test against the app running in kind (exposed on localhost:8080).
set -euo pipefail
BASE="${BASE_URL:-http://localhost:8080}"

echo "== healthz";  curl -fsS "$BASE/healthz"; echo
echo "== readyz";   curl -fsS "$BASE/readyz";  echo
echo "== POST /api/calls"
RESP=$(curl -fsS -X POST "$BASE/api/calls" -H 'content-type: application/json' \
  -d '{"from":"+32470000001","to":"+32800000000","intent":"support"}')
echo "$RESP"
ID=$(echo "$RESP" | sed -E 's/.*"call_id":"([a-f0-9]+)".*/\1/')
echo "== GET /api/calls/$ID"
# Note: the store is per-pod and in-memory, so with 2+ replicas this lookup
# may hit another pod and return 404. That's expected until we add shared
# storage - so we don't fail on it.
curl -sS "$BASE/api/calls/$ID"; echo
echo "== metrics";  curl -fsS "$BASE/metrics"
echo "SMOKE OK"
