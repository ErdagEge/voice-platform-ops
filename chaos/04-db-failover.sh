#!/usr/bin/env bash
# Experiment 4: kill the PostgreSQL primary pod under load (CNPG failover).
EXPERIMENT=04-db-failover
# shellcheck source=chaos/lib.sh
source "$(dirname "$0")/lib.sh"
DURATION="${DURATION:-90}" WORKERS="${WORKERS:-4}"
out=$(mktemp)

old=$(primary); log "primary before: $old"; db_pods | sed 's/^/  /'
load_start "$DURATION" "$WORKERS" "$out"
sleep 15
log "force-deleting primary $old"
t0=$(date +%s)
kubectl -n "$NAMESPACE" delete pod "$old" --grace-period=0 --force >/dev/null 2>&1
new=""; until [ -n "$new" ] && [ "$new" != "$old" ]; do new=$(primary); sleep 1; [ $(( $(date +%s) - t0 )) -gt 120 ] && break; done
promoted=$(( $(date +%s) - t0 )); log "new primary: $new after ${promoted}s"
load_wait
summary=$(load_summary "$out"); missing=$(verify_ids "$out")
first=$(sed -E 's/.*first_err_ms=([0-9]+).*/\1/' <<<"$summary"); last=$(sed -E 's/.*last_err_ms=([0-9]+).*/\1/' <<<"$summary")
win=$([ "$first" != 0 ] && echo "$(( (last - first) / 1000 ))s (t+$(( first / 1000 - t0 ))s .. t+$(( last / 1000 - t0 ))s)" || echo "none")
log "$summary codes: $(load_codes "$out") lost_calls=$missing error window: $win"
kubectl -n "$NAMESPACE" wait --for=condition=Ready cluster/call-router-db --timeout=300s >/dev/null || true
log "after:"; db_pods | sed 's/^/  /'
restarts=$(kubectl -n "$NAMESPACE" get pods -l app.kubernetes.io/name=call-router -o jsonpath='{range .items[*]}{.status.containerStatuses[0].restartCount} {end}')

HYPOTHESIS="If the PostgreSQL primary dies, CloudNativePG promotes the replica within 30 s; the app reconnects on its own (no pod restarts), errors are limited to that window, and no acknowledged call is lost."
METHOD="$WORKERS workers of POST+GET for ${DURATION}s. At t=15s: \`kubectl delete pod $old --grace-period=0 --force\` (primary)."
RESULT="- Requests: \`$summary\` codes \`$(load_codes "$out")\`
- New primary \`$new\` after **${promoted}s**; error window: **$win**
- App container restarts during the test: \`$restarts\` (unchanged = 0 new)
- Acknowledged calls lost: **$missing** of $(wc -l <"$out.ids")"
VERDICT=$([ "$promoted" -le 30 ] && [ "$missing" = 0 ] && echo "PASS - failover within ${promoted}s, no data loss." || echo "FAIL - see result.")
report "$EXPERIMENT"
rm -f "$out" "$out.ids"
