#!/usr/bin/env bash
# Experiment 2: planned maintenance - drain a worker node under load.
EXPERIMENT=02-node-drain
# shellcheck source=chaos/lib.sh
source "$(dirname "$0")/lib.sh"
DURATION="${DURATION:-120}" WORKERS="${WORKERS:-4}"
out=$(mktemp)

# Default victim: the node hosting the PostgreSQL primary (the hardest case:
# CloudNativePG must switch over before the primary pod can be evicted).
old_primary=$(primary)
node="${NODE:-$(kubectl -n "$NAMESPACE" get pod "$old_primary" -o jsonpath='{.spec.nodeName}')}"
log "before:"; app_pods | sed 's/^/  app /'; db_pods | sed 's/^/  db  /'
load_start "$DURATION" "$WORKERS" "$out"
sleep 15
log "draining $node (PDBs are respected)"
t0=$(date +%s)
kubectl drain "$node" --ignore-daemonsets --delete-emptydir-data --timeout=180s >/dev/null 2>&1 || log "drain timed out (PDB kept a pod?)"
drain_s=$(( $(date +%s) - t0 ))
log "drain finished in ${drain_s}s"; app_pods | sed 's/^/  app /'; db_pods | sed 's/^/  db  /'
spread=$(kubectl -n "$NAMESPACE" get pods -l app.kubernetes.io/name=call-router -o jsonpath='{range .items[*]}{.status.phase}/{.spec.nodeName} {end}')
load_wait
summary=$(load_summary "$out"); missing=$(verify_ids "$out")
log "$summary codes: $(load_codes "$out") lost_calls=$missing"
log "uncordon $node"; kubectl uncordon "$node" >/dev/null
sleep 5
kubectl -n "$NAMESPACE" wait --for=condition=Ready cluster/call-router-db --timeout=300s >/dev/null || true
new_primary=$(primary)
log "after uncordon:"; app_pods | sed 's/^/  app /'; db_pods | sed 's/^/  db  /'
# Topology spread is only checked at scheduling time: both app pods now sit on the
# same node and stay there. A rolling restart spreads them again (in production a
# descheduler does this automatically).
log "rebalancing app pods with a rolling restart"
kubectl -n "$NAMESPACE" rollout restart deployment/call-router >/dev/null
kubectl -n "$NAMESPACE" rollout status deployment/call-router --timeout=180s >/dev/null
# rollout status returns while old pods are still Terminating; wait until they are gone.
for _ in $(seq 60); do [ "$(app_pods | wc -l)" -le 2 ] && break; sleep 2; done
rebalanced=$(app_pods | awk '{printf "%s ", $4}')
errs=$(sed -E 's/.*errors=([0-9]+).*/\1/' <<<"$summary")

HYPOTHESIS="Draining a worker (planned maintenance) causes zero failed requests: pods are evicted gracefully one at a time (PodDisruptionBudget), the hard topology spread still lets the evicted app pod move to the remaining node (cordoned nodes are ignored), and CloudNativePG switches the primary away before evicting it."
METHOD="$WORKERS workers of POST+GET for ${DURATION}s. At t=15s: \`kubectl drain $node --ignore-daemonsets --delete-emptydir-data\`, then \`kubectl uncordon\` at the end."
RESULT="- Requests: \`$summary\` codes \`$(load_codes "$out")\`
- Drain took ${drain_s}s; app pods during drain: \`$spread\`
- Calls lost: **$missing**
- PostgreSQL primary: before \`$old_primary\`, after \`$new_primary\`
- After uncordon both app pods were still on the same node (spread is enforced only when scheduling); after a rolling restart they run on: \`$rebalanced\`
- Note: the PostgreSQL instance on the drained node stays Pending until uncordon - its volume is node-local (local-path) and the other worker already hosts the other instance (required anti-affinity). The cluster ran on one instance meanwhile (CallRouterDatabaseNoReplica would open a ticket after 10 min)."
VERDICT=$([ "$errs" = 0 ] && [ "$missing" = 0 ] && echo "PASS - zero errors during a node drain." || echo "PARTIAL/FAIL - $errs failed requests during the drain; see result.")
report "$EXPERIMENT"
rm -f "$out" "$out.ids"
