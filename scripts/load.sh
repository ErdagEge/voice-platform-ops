#!/usr/bin/env bash
# Simple traffic generator (no extra tools): N parallel curl loops for
# DURATION seconds against BASE_URL, mixing intents and some bad requests.
#   DURATION=120 CONCURRENCY=4 scripts/load.sh
set -euo pipefail
BASE_URL="${BASE_URL:-http://localhost:8080}"
DURATION="${DURATION:-120}"
CONCURRENCY="${CONCURRENCY:-4}"
intents=(buy pricing support billing help weather "")

worker() {
  local end=$((SECONDS + DURATION)) ok=0 err=0 i=0 code
  while [ "$SECONDS" -lt "$end" ]; do
    i=$((i + 1))
    body="{\"from\":\"+3247000$RANDOM\",\"to\":\"+32800000000\",\"intent\":\"${intents[$((i % ${#intents[@]}))]}\"}"
    # Every 50th request is invalid (-> 422), to exercise the validation path.
    [ $((i % 50)) -eq 0 ] && body='{}'
    code=$(curl -s -m 5 -o /dev/null -w '%{http_code}' -X POST "$BASE_URL/api/calls" \
      -H 'content-type: application/json' -d "$body" || echo 000)
    case "$code" in 2*|422) ok=$((ok + 1)) ;; *) err=$((err + 1)) ;; esac
  done
  echo "worker $1: ok=$ok errors=$err"
}

echo "load: $CONCURRENCY workers x ${DURATION}s against $BASE_URL"
for w in $(seq "$CONCURRENCY"); do worker "$w" & done
wait
