#!/usr/bin/env bash
# Experiment 6: injected latency. Every POST /api/calls gets +LATENCY_MS
# (FAULT_LATENCY_MS, see CallRouter.FaultInjection) - like a slow dependency.
#
# Default 25 minutes. The fast-burn page needs the 15-minute bad ratio (and
# `for: 2m`) above 14.4%. The original 8-minute run could not reach that, and
# the old 1-hour window was diluted by earlier fast traffic. MINUTES=8
# reproduces that miss.
EXPERIMENT=06-latency
# shellcheck source=chaos/lib.sh
source "$(dirname "$0")/lib.sh"
LATENCY_MS="${LATENCY_MS:-600}" MINUTES="${MINUTES:-25}" WORKERS="${WORKERS:-4}"
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
sli5=$(prom 'slo:sli_error:ratio_rate5m{slo="call-router-latency"}')
sli15=$(prom 'slo:sli_error:ratio_rate15m{slo="call-router-latency"}')
sli1h=$(prom 'slo:sli_error:ratio_rate1h{slo="call-router-latency"}')
load_wait
summary=$(load_summary "$out")
log "$summary p99=${p99}s latency-SLI-5m=${sli5} 15m=${sli15} 1h=${sli1h} alert after ${fired:-never}s"
log "removing the latency"
helm_set 0

HYPOTHESIS="A dependency adding ${LATENCY_MS} ms to every POST /api/calls (above the 500 ms SLO threshold) does not cause errors, but the latency fast-burn page (15m and 5m bad ratio above 14.4%) fires within this ${MINUTES}-minute run."
METHOD="\`helm upgrade --set config.faultLatencyMs=$LATENCY_MS\` (rolling update), then $WORKERS workers of POST+GET for $MINUTES minutes; finally back to 0."
RESULT="- Requests: \`$summary\`
- POST p99 latency (2m): **${p99}s**
- Latency SLI bad ratio: 5m **${sli5}**, 15m **${sli15}**, 1h **${sli1h}**
- CallRouterLatencyBudgetBurnFast firing after: **${fired:-did not fire within ${MINUTES} min}${fired:+s}**"
VERDICT=$([ -n "$fired" ] && echo "PASS - latency is detected by the SLO alert, not by error counts." || echo "FAIL - alert did not fire within ${MINUTES} minutes.")
BACKGROUND=$(cat <<'EOF'
Original run (2026-10-20 22:05 CEST, `MINUTES=8`) **FAIL**ed: 0 errors, POST p99 0.75 s, 5-minute latency bad ratio 50%, but `CallRouterLatencyBudgetBurnFast` never fired. The 1-hour bad ratio peaked at 1.45% because about 212 000 earlier fast requests diluted `rate()[1h]`. At a steady 50% bad ratio that 1h window needs about 17 minutes plus `for: 2m` to cross 14.4%, and the slower request rate during the injection (slow POSTs throttle the load generator) makes it worse. Re-running for 25 minutes on that busy cluster would still have missed.

Fix: the latency fast-burn long window is **15m** (still AND the 5m window, still 14.4x the 1% budget, still `for: 2m`). Fifteen minutes of bad latency is not diluted by the previous hour. Availability burn rates are unchanged. Promtool covers the diluted shape: fast traffic for an hour, then 50% slow at a lower rate; the 1h ratio stays under 14.4% and the page still fires, and it does not fire at the 8-minute mark.

Re-verify (kind up, Prometheus on localhost:9090): `bash chaos/06-latency.sh` (default `MINUTES=25`). The page should fire inside that window. `MINUTES=8 bash chaos/06-latency.sh` is the original failing duration.
EOF
)
report "$EXPERIMENT"
rm -f "$out" "$out.ids"
