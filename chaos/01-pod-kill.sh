#!/usr/bin/env bash
# Experiment 1: kill an app pod under load. Three modes:
#   MODE=sigkill  (default) SIGKILL the container on its node with crictl - a real
#                 crash: no SIGTERM, no draining; the pod stays and kubelet restarts it.
#   MODE=force    `kubectl delete --grace-period=0 --force`: the pod object vanishes at
#                 once (endpoint removed) and kubelet still sends SIGTERM to the process.
#   MODE=graceful normal delete (preStop + SIGTERM), exactly what a rollout does.
EXPERIMENT=01-pod-kill
# shellcheck source=chaos/lib.sh
source "$(dirname "$0")/lib.sh"
MODE="${MODE:-sigkill}" DURATION="${DURATION:-60}" WORKERS="${WORKERS:-4}"
MAX_ERROR_PCT="${MAX_ERROR_PCT:-1}"
out=$(mktemp)

log "pods before:"; app_pods | sed 's/^/  /'
load_start "$DURATION" "$WORKERS" "$out"
sleep 15
victim=$(kubectl -n "$NAMESPACE" get pods -l app.kubernetes.io/name=call-router -o jsonpath='{.items[0].metadata.name}')
log "killing $victim ($MODE)"
if [ "$MODE" = sigkill ]; then
  node=$(kubectl -n "$NAMESPACE" get pod "$victim" -o jsonpath='{.spec.nodeName}')
  cid=$(kubectl -n "$NAMESPACE" get pod "$victim" -o jsonpath='{.status.containerStatuses[0].containerID}')
  # `crictl stop --timeout 0` = SIGKILL straight away (kind nodes are docker containers).
  docker exec "$node" crictl stop --timeout 0 "${cid#containerd://}" >/dev/null
  action="SIGKILL of the container on $node (\`crictl stop --timeout 0\`); kubelet restarts it in place"
elif [ "$MODE" = force ]; then
  kubectl -n "$NAMESPACE" delete pod "$victim" --grace-period=0 --force >/dev/null 2>&1
  action="\`kubectl delete pod $victim --grace-period=0 --force\`"
else
  action="\`kubectl delete pod $victim\` (graceful)"
  kubectl -n "$NAMESPACE" delete pod "$victim" --wait=false >/dev/null
fi
sleep 2
recovery=$(( $(wait_app_ready 120) + 2 ))
log "all replicas Ready again ${recovery}s after the kill"
load_wait
summary=$(load_summary "$out"); missing=$(verify_ids "$out")
alerts=$(firing_alerts)
log "$summary codes: $(load_codes "$out") lost_calls=$missing"
log "pods after:"; app_pods | sed 's/^/  /'
pct=$(sed -E 's/.*error_pct=([0-9.]+).*/\1/' <<<"$summary")
ok=$(awk -v p="$pct" -v m="$MAX_ERROR_PCT" 'BEGIN { print (p <= m) ? "yes" : "no" }')

HYPOTHESIS="Killing one of two replicas ($MODE) under load causes at most ${MAX_ERROR_PCT}% failed requests, all replicas are Ready again within 60 s, no stored call is lost, and no SLO alert fires."
METHOD="$WORKERS workers sending POST /api/calls + GET for ${DURATION}s through the NodePort (new connection per request). At t=15s: $action. Afterwards every created call id is read back."
RESULT="- Requests: \`$summary\`
- Error codes: \`$(load_codes "$out")\` (000 = connection refused/reset/timeout)
- All replicas Ready again after: **${recovery}s**
- Alerts pending/firing right after the run: \`${alerts:-none}\`
- Calls lost: **$missing** of $(wc -l <"$out.ids")
- Pods after: $(app_pods | awk '{printf "%s on %s (restarts %s); ", $1, $4, $5}')"
VERDICT=$([ "$ok" = yes ] && [ "$missing" = 0 ] && echo "PASS - hypothesis held." || echo "FAIL - see result; error rate above ${MAX_ERROR_PCT}% or data lost.")
report "$EXPERIMENT-$MODE"
rm -f "$out" "$out.ids"
[ "$ok" = yes ] && [ "$missing" = 0 ]
