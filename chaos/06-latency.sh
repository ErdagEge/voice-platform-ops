#!/usr/bin/env bash
# Experiment 6: injected latency. Every POST /api/calls gets +LATENCY_MS
# (FAULT_LATENCY_MS, see CallRouter.FaultInjection) - like a slow dependency.
EXPERIMENT=06-latency
# shellcheck source=chaos/lib.sh
source "$(dirname "$0")/lib.sh"
LATENCY_MS="${LATENCY_MS:-600}" MINUTES="${MINUTES:-8}" WORKERS="${WORKERS:-4}"
out=$(mktemp)
helm_set() {
  IMAGE_REPO=voice-platform-ops/call_router IMAGE_TAG="${IMAGE_TAG:-local}" SKIP_SMOKE=true \
  VALUES_FILES="$ROOT/deploy/helm/call-router/values-local.yaml" HELM_EXTRA_ARGS="--set config.faultLatencyMs=$1" \
    "$ROOT/scripts/deploy.sh" >/dev/null
}
log "injecting ${LATENCY_MS} ms latency on POST /api/calls (rolling update)"
helm_set "$LATENCY_MS"
t0=$(date +%s)
load_start $(( MINUTES * 60 )) "$WORKERS" "$out"
fired=""
while [ $(( $(date +%s) - t0 )) -lt $(( MINUTES * 60 )) ]; do
  s=$(alert_state CallRouterLatencyBudgetBurnFast)
  [ -z "$fired" ] && [ "$s" = firing ] && { fired=$(( $(date +%s) - t0 )); log "CallRouterLatencyBudgetBurnFast FIRING after ${fired}s"; }
  sleep 10
done
p99=$(prom 'histogram_quantile(0.99, sum by (le) (rate(http_request_duration_seconds_bucket{job="call-router",route="/api/calls",method="POST"}[2m])))')
sli=$(prom 'slo:sli_error:ratio_rate5m{slo="call-router-latency"}')
load_wait
summary=$(load_summary "$out")
log "$summary p99=${p99}s latency-SLI-5m=${sli} alert after ${fired:-never}s"
log "removing the latency"
helm_set 0

HYPOTHESIS="A dependency adding ${LATENCY_MS} ms to every call (above the 500 ms SLO threshold) does not cause errors, but burns the latency error budget fast enough for CallRouterLatencyBudgetBurnFast to page within ~10 minutes."
METHOD="\`helm upgrade --set config.faultLatencyMs=$LATENCY_MS\` (rolling update), then $WORKERS workers of POST+GET for $MINUTES minutes; finally back to 0."
RESULT="- Requests: \`$summary\`
- POST p99 latency (2m): **${p99}s**; latency SLI (bad ratio, 5m): **${sli}**
- CallRouterLatencyBudgetBurnFast firing after: **${fired:-did not fire within ${MINUTES} min}${fired:+s}**"
VERDICT=$([ -n "$fired" ] && echo "PASS - latency is detected by the SLO alert, not by error counts." || echo "FAIL - alert did not fire within ${MINUTES} minutes.")
report "$EXPERIMENT"
rm -f "$out" "$out.ids"
