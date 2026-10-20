#!/usr/bin/env bash
# Experiment 3: unplanned node failure - stop a kind worker's container
# (like pulling the power cord) under load, then start it again.
EXPERIMENT=03-node-failure
# shellcheck source=chaos/lib.sh
source "$(dirname "$0")/lib.sh"
DOWN_SECONDS="${DOWN_SECONDS:-120}" WORKERS="${WORKERS:-4}"
DURATION=$(( DOWN_SECONDS + 60 ))
out=$(mktemp)

# Prefer the node that runs the DB primary: worst case (app pod + primary).
node=$(kubectl -n "$NAMESPACE" get pod "$(primary)" -o jsonpath='{.spec.nodeName}')
log "before (victim node: $node):"; app_pods | sed 's/^/  app /'; db_pods | sed 's/^/  db  /'
load_start "$DURATION" "$WORKERS" "$out"
sleep 15
log "docker stop $node"
t0=$(date +%s); sudo docker stop "$node" >/dev/null 2>&1 || docker stop "$node" >/dev/null
notready=""; newprimary=""
while [ $(( $(date +%s) - t0 )) -lt "$DOWN_SECONDS" ]; do
  if [ -z "$notready" ] && kubectl get node "$node" --no-headers 2>/dev/null | grep -q NotReady; then
    notready=$(( $(date +%s) - t0 )); log "node NotReady after ${notready}s"; fi
  p=$(primary 2>/dev/null || true)
  if [ -z "$newprimary" ] && [ -n "$p" ] && [ "$(kubectl -n "$NAMESPACE" get pod "$p" -o jsonpath='{.spec.nodeName}' 2>/dev/null)" != "$node" ]; then
    newprimary=$(( $(date +%s) - t0 )); log "new primary $p after ${newprimary}s"; fi
  sleep 2
done
log "docker start $node"
sudo docker start "$node" >/dev/null 2>&1 || docker start "$node" >/dev/null
load_wait
summary=$(load_summary "$out"); missing=$(verify_ids "$out")
first=$(sed -E 's/.*first_err_ms=([0-9]+).*/\1/' <<<"$summary"); last=$(sed -E 's/.*last_err_ms=([0-9]+).*/\1/' <<<"$summary")
err_from=$([ "$first" != 0 ] && echo $(( first / 1000 - t0 )) || echo -); err_to=$([ "$last" != 0 ] && echo $(( last / 1000 - t0 )) || echo -)
log "$summary codes: $(load_codes "$out") lost_calls=$missing errors from t+${err_from}s to t+${err_to}s"
kubectl wait --for=condition=Ready "node/$node" --timeout=180s >/dev/null || true
kubectl -n "$NAMESPACE" wait --for=condition=Ready cluster/call-router-db --timeout=300s >/dev/null || true
log "after restart:"; app_pods | sed 's/^/  app /'; db_pods | sed 's/^/  db  /'

HYPOTHESIS="When the worker running one app replica AND the PostgreSQL primary dies, CloudNativePG promotes the replica and the surviving app replica keeps serving; requests fail only until the failure is detected (< 60 s), and no acknowledged call is lost."
METHOD="$WORKERS workers of POST+GET for ${DURATION}s. At t=15s: \`docker stop $node\` (the kind node container), restarted after ${DOWN_SECONDS}s."
RESULT="- Requests: \`$summary\` codes \`$(load_codes "$out")\`
- Errors from t+${err_from}s to t+${err_to}s after the node died
- Node marked NotReady after: **${notready:-n/a}s**; new DB primary after: **${newprimary:-n/a}s**
- Acknowledged calls lost: **$missing** of $(wc -l <"$out.ids")"
win=$(sed -E 's/.*err_window_s=([0-9.]+).*/\1/' <<<"$summary")
VERDICT=$(awk -v w="$win" -v m="$missing" 'BEGIN { if (w <= 60 && m == 0) print "PASS - errors stopped within 60 s, no call lost."; else printf "FAIL - error window %ss (limit 60 s), %s calls lost.\n", w, m }')
report "$EXPERIMENT"
rm -f "$out" "$out.ids"
