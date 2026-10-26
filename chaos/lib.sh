#!/usr/bin/env bash
# Shared helpers for the chaos experiments (sourced, not run).
#
# Load: N workers loop POST /api/calls + GET /api/calls/:id and log one line
# per request: "<epoch-ms> <http-status>". Status 000 = no HTTP answer
# (connection refused / reset / 2 s timeout) - what a caller would see as a
# failed call, even though the app's own metrics never saw the request.
set -euo pipefail
CHAOS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC2034  # used by the experiment scripts that source this file
ROOT="$(cd "$CHAOS_DIR/.." && pwd)"
NAMESPACE="${NAMESPACE:-voice}"
BASE_URL="${BASE_URL:-http://localhost:8080}"
PROM_URL="${PROM_URL:-http://localhost:9090}"
RESULTS="${RESULTS:-$CHAOS_DIR/results}"
log() { printf '[%s] %s %s\n' "${EXPERIMENT:-chaos}" "$(date +%T)" "$*"; }
ms() { date +%s%3N; }

_worker() {
  local out="$1" until="$2" id code
  while [ "$(date +%s)" -lt "$until" ]; do
    body=$(curl -s -m 2 -w ' %{http_code}' -X POST "$BASE_URL/api/calls" \
      -H 'content-type: application/json' -d '{"from":"+32470000001","to":"+32800000000","intent":"support"}' || true)
    code="${body##* }"; echo "$(ms) ${code:-000}" >>"$out"
    id=$(grep -o '"call_id":"[0-9a-f]*"' <<<"$body" | cut -d'"' -f4 || true)
    if [ -n "$id" ]; then
      echo "$id" >>"$out.ids"
      code=$(curl -s -o /dev/null -m 2 -w '%{http_code}' "$BASE_URL/api/calls/$id" || true)
      echo "$(ms) ${code:-000}" >>"$out"
    fi
  done
}

# load_start <seconds> <workers> <logfile>   (runs in the background)
load_start() {
  local until=$(( $(date +%s) + $1 ))
  : >"$3"; : >"$3.ids"
  for _ in $(seq "$2"); do _worker "$3" "$until" & done
}

load_wait() { wait; }

# load_summary <logfile> -> "total=.. ok=.. errors=.. error_pct=.. first_err=.. last_err=.. err_window_s=.."
load_summary() {
  sort -n "$1" | awk '
    { total++; if ($2 ~ /^(2..|404)$/) ok++; else { err++; if (!first) first=$1; last=$1 } }
    END {
      pct = total ? 100 * err / total : 0
      win = err ? (last - first) / 1000 : 0
      printf "total=%d ok=%d errors=%d error_pct=%.2f err_window_s=%.1f first_err_ms=%s last_err_ms=%s\n",
        total, ok, err, pct, win, (first ? first : 0), (last ? last : 0)
    }'
}

# Error codes breakdown, e.g. "000:12 503:3"
load_codes() { awk '$2 !~ /^(2..|404)$/ { c[$2]++ } END { for (k in c) printf "%s:%d ", k, c[k] }' "$1"; }

# Every id that got a 201 must still be readable at the end (no data loss).
verify_ids() {
  local missing=0 id
  while read -r id; do
    [ "$(curl -s -o /dev/null -m 3 -w '%{http_code}' "$BASE_URL/api/calls/$id")" = 200 ] || missing=$((missing + 1))
  done <"$1.ids"
  echo "$missing"
}

# Instant PromQL query -> first value (empty if none / Prometheus unreachable).
prom() {
  curl -s -m 5 -G "$PROM_URL/api/v1/query" --data-urlencode "query=$1" 2>/dev/null \
    | grep -o '"value":\[[^]]*\]' | head -1 | sed -E 's/.*,"([^"]*)"\]/\1/' || true
}

# Firing/pending state of an alert ("firing", "pending" or "").
alert_state() {
  curl -s -m 5 "$PROM_URL/api/v1/alerts" 2>/dev/null | tr '{' '\n' \
    | grep "\"alertname\":\"$1\"" -A3 | grep -o '"state":"[a-z]*"' | head -1 | cut -d'"' -f4 || true
}

# Names of all alerts that are pending or firing (except the always-on Watchdog),
# e.g. "CallRouterDatabaseDown(firing) ". Empty string = nothing alerting.
firing_alerts() {
  curl -sf -m 5 "$PROM_URL/-/ready" >/dev/null 2>&1 || { echo "n/a (no Prometheus at $PROM_URL)"; return 0; }
  curl -s -m 5 "$PROM_URL/api/v1/alerts" 2>/dev/null | python3 -c '
import json, sys
try: alerts = json.load(sys.stdin)["data"]["alerts"]
except Exception: sys.exit(0)
print(" ".join(sorted({a["labels"]["alertname"] + "(" + a["state"] + ")" for a in alerts
                        if a["labels"]["alertname"] != "Watchdog"})))' || true
}

# Wait until all app pods are Ready again; prints seconds waited.
wait_app_ready() {
  local start; start=$(date +%s)
  kubectl -n "$NAMESPACE" rollout status deploy/call-router --timeout="${1:-300}s" >/dev/null
  until [ "$(kubectl -n "$NAMESPACE" get deploy call-router -o jsonpath='{.status.readyReplicas}')" = \
          "$(kubectl -n "$NAMESPACE" get deploy call-router -o jsonpath='{.spec.replicas}')" ]; do sleep 1; done
  echo $(( $(date +%s) - start ))
}

# custom-columns keeps the column positions fixed (the RESTARTS column of `-o wide`
# contains spaces like "1 (2m ago)" after a restart, which shifts awk fields).
app_pods() { kubectl -n "$NAMESPACE" get pods -l app.kubernetes.io/name=call-router --no-headers \
  -o custom-columns='NAME:.metadata.name,READY:.status.containerStatuses[0].ready,PHASE:.status.phase,NODE:.spec.nodeName,RESTARTS:.status.containerStatuses[0].restartCount'; }
db_pods() { kubectl -n "$NAMESPACE" get pods -l cnpg.io/cluster=call-router-db --no-headers \
  -o custom-columns='NAME:.metadata.name,READY:.status.containerStatuses[0].ready,PHASE:.status.phase,NODE:.spec.nodeName,ROLE:.metadata.labels.cnpg\.io/instanceRole'; }
primary() { kubectl -n "$NAMESPACE" get cluster call-router-db -o jsonpath='{.status.currentPrimary}'; }

# report <name> : write $RESULTS/<name>.md from the HYPOTHESIS / METHOD / RESULT / VERDICT variables.
# Optional BACKGROUND is appended (find -> fix notes that should survive a re-run).
report() {
  mkdir -p "$RESULTS"
  background=""
  if [ -n "${BACKGROUND:-}" ]; then
    background="
## Background
${BACKGROUND}"
  fi
  cat >"$RESULTS/$1.md" <<MD
# Chaos experiment: $1

Run: $(TZ=Europe/Brussels date '+%Y-%m-%d %H:%M %Z') on kind ($(kubectl get nodes --no-headers | wc -l) nodes), $(kubectl -n "$NAMESPACE" get deploy call-router -o jsonpath='{.spec.replicas}') app replicas, $(kubectl -n "$NAMESPACE" get pods -l cnpg.io/cluster=call-router-db --no-headers 2>/dev/null | wc -l) PostgreSQL instance(s).

## Hypothesis
${HYPOTHESIS:?}

## Method
${METHOD:?}

## Result
${RESULT:?}

## Verdict
${VERDICT:?}
${background}
MD
  log "report: $RESULTS/$1.md"
}
