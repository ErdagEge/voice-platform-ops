#!/usr/bin/env bash
# Experiment 5: total database outage for DOWN_SECONDS, then bring it back.
#   INJECT=fence (default) CNPG fencing of all instances: PostgreSQL is stopped
#                immediately (fast shutdown), pods stay - like a crashed database.
#   INJECT=hibernate       CNPG hibernation: graceful (smart) shutdown, pods deleted,
#                volumes kept - like a planned stop. Waits for client connections
#                to close (up to smartShutdownTimeout = 180 s by default)!
EXPERIMENT=05-db-down
# shellcheck source=chaos/lib.sh
source "$(dirname "$0")/lib.sh"
DOWN_SECONDS="${DOWN_SECONDS:-240}" WORKERS="${WORKERS:-2}" INJECT="${INJECT:-fence}"
DURATION=$(( DOWN_SECONDS + 150 ))
KIND="$INJECT"
out=$(mktemp)

log "before:"; db_pods | sed 's/^/  /'; app_pods | sed 's/^/  /'
restarts_before=$(kubectl -n "$NAMESPACE" get pods -l app.kubernetes.io/name=call-router -o jsonpath='{range .items[*]}{.status.containerStatuses[0].restartCount} {end}')
load_start "$DURATION" "$WORKERS" "$out"
sleep 20
secs_or_never() { if [ -n "$1" ]; then echo "${1}s"; else echo never; fi; }
db_down() {
  if [ "$INJECT" = hibernate ]; then
    kubectl -n "$NAMESPACE" annotate cluster call-router-db --overwrite cnpg.io/hibernation=on >/dev/null
  else
    kubectl -n "$NAMESPACE" annotate cluster call-router-db --overwrite 'cnpg.io/fencedInstances=["*"]' >/dev/null
  fi
}
db_up() {
  if [ "$INJECT" = hibernate ]; then
    kubectl -n "$NAMESPACE" annotate cluster call-router-db --overwrite cnpg.io/hibernation=off >/dev/null
  else
    kubectl -n "$NAMESPACE" annotate cluster call-router-db 'cnpg.io/fencedInstances-' >/dev/null
  fi
}
log "DB DOWN: $INJECT all instances of cluster call-router-db"
mkdir -p "$RESULTS"; t0=$(date +%s); echo "$t0" >"$RESULTS/.05-db-down-$INJECT.t"
db_down
unready="" fired="" pend=""
while [ $(( $(date +%s) - t0 )) -lt "$DOWN_SECONDS" ]; do
  r=$(kubectl -n "$NAMESPACE" get deploy call-router -o jsonpath='{.status.readyReplicas}')
  [ -z "$unready" ] && [ "${r:-0}" = 0 ] && { unready=$(( $(date +%s) - t0 )); log "all app pods NotReady after ${unready}s"; }
  s=$(alert_state CallRouterDatabaseDown)
  [ -z "$pend" ] && [ -n "$s" ] && { pend=$(( $(date +%s) - t0 )); log "CallRouterDatabaseDown $s after ${pend}s"; }
  [ -z "$fired" ] && [ "$s" = firing ] && { fired=$(( $(date +%s) - t0 )); log "CallRouterDatabaseDown FIRING after ${fired}s"; }
  sleep 3
done
avail=$(alert_state CallRouterAvailabilityBudgetBurnFast)
log "DB UP: waking the cluster (availability burn alert state while down: '${avail:-none}')"
t1=$(date +%s)
db_up
for _ in $(seq 150); do
  [ "$(kubectl -n "$NAMESPACE" get deploy call-router -o jsonpath='{.status.readyReplicas}')" = 2 ] && break; sleep 2
done
back=$(( $(date +%s) - t1 )); log "app Ready again ${back}s after the DB was started"
load_wait
summary=$(load_summary "$out"); missing=$(verify_ids "$out")
restarts_after=$(kubectl -n "$NAMESPACE" get pods -l app.kubernetes.io/name=call-router -o jsonpath='{range .items[*]}{.status.containerStatuses[0].restartCount} {end}')
log "$summary codes: $(load_codes "$out") lost_calls=$missing restarts ${restarts_before}-> ${restarts_after}"
echo "$t1 $(date +%s)" >>"$RESULTS/.05-db-down-$INJECT.t"

HYPOTHESIS="With the database completely down: readiness fails on all app pods within 15 s (traffic stops instead of erroring slowly), liveness does NOT restart them, CallRouterDatabaseDown pages within 2 minutes, and service recovers by itself within 60 s after the database is back, with no acknowledged call lost."
if [ "$INJECT" = hibernate ]; then
  how="\`kubectl annotate cluster call-router-db cnpg.io/hibernation=on\` (graceful shutdown, pods removed, volumes kept); after ${DOWN_SECONDS}s \`hibernation=off\`"
else
  how="\`kubectl annotate cluster call-router-db 'cnpg.io/fencedInstances=[\"*\"]'\` (every PostgreSQL instance stopped at once, pods stay); after ${DOWN_SECONDS}s the annotation is removed"
fi
METHOD="$WORKERS workers of POST+GET for ${DURATION}s. At t=20s: $how."
RESULT="- Requests: \`$summary\` codes \`$(load_codes "$out")\`
- All app pods NotReady after: **$(secs_or_never "$unready")**
- CallRouterDatabaseDown pending after **$(secs_or_never "$pend")**, firing after **$(secs_or_never "$fired")**
- CallRouterAvailabilityBudgetBurnFast while down: **${avail:-not active}**
- App Ready again **${back}s** after the DB came back; container restarts: \`${restarts_before}\` -> \`${restarts_after}\`
- Acknowledged calls lost: **$missing**"
VERDICT="See result and docs/postmortems/2026-10-20-database-outage.md."
report "$EXPERIMENT-$KIND"
rm -f "$out" "$out.ids"
