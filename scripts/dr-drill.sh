#!/usr/bin/env bash
# Disaster-recovery drill on kind: prove that backups restore, and measure
# RPO (how much data was lost) and RTO (how long until service is back).
#
#   1. write known calls (set A), take a backup
#   2. keep writing one call per second for TRICKLE_SECONDS (set B)
#   3. DISASTER: delete the whole namespace (DB pods, volumes, app, secrets)
#   4. restore: S3 credentials -> DB from backup + WAL -> app -> alert rules
#   5. verify every call of set A is back; count which calls of set B survived
#
#   scripts/dr-drill.sh        # CALLS_BEFORE [20], TRICKLE_SECONDS [75]
#
# Writes a report to docs/dr-drills/<date>-dr-drill.md. Times are local
# (Europe/Brussels on this box).
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export NAMESPACE="${NAMESPACE:-voice}"
BASE_URL="${BASE_URL:-http://localhost:8080}"
CALLS_BEFORE="${CALLS_BEFORE:-20}"
TRICKLE_SECONDS="${TRICKLE_SECONDS:-75}"
WORK="$(mktemp -d)"
REPORT="${REPORT:-$ROOT/docs/dr-drills/$(date +%Y-%m-%d-%H%M)-dr-drill.md}"
log() { printf '[dr-drill] %s %s\n' "$(date +%T)" "$*"; }
now() { date +%s.%N; }
hms() { date -d "@${1%.*}" +%T; }
secs() { awk -v a="$1" -v b="$2" 'BEGIN { printf "%.0f", a - b }'; } # a - b, rounded

# POST a call, append "<id> <created_at>" to a file.
write_call() {
  local body
  body=$(curl -fsS -m 5 -X POST "$BASE_URL/api/calls" -H 'content-type: application/json' \
    -d "{\"from\":\"+3247000$RANDOM\",\"to\":\"+32800000000\",\"intent\":\"dr-drill\"}") || return 1
  field() { grep -o "\"$1\":\"[^\"]*\"" <<<"$body" | cut -d'"' -f4; }
  echo "$(field call_id) $(field created_at)" >>"$1"
}
present() { [ "$(curl -s -o /dev/null -w '%{http_code}' -m 5 "$BASE_URL/api/calls/$1")" = 200 ]; }

log "precheck: app must be healthy"
curl -fsS -m 5 "$BASE_URL/readyz" >/dev/null
old_server=$(kubectl -n "$NAMESPACE" get cluster call-router-db -o jsonpath='{.spec.plugins[0].parameters.serverName}')

log "1/5 writing $CALLS_BEFORE calls (set A) and taking a backup"
for _ in $(seq "$CALLS_BEFORE"); do write_call "$WORK/a.txt"; done
"$ROOT/scripts/backup.sh" | sed 's/^/  /'
t_backup=$(now)

log "2/5 writing 1 call/s for ${TRICKLE_SECONDS}s after the backup (set B - only WAL protects these)"
end=$(( $(date +%s) + TRICKLE_SECONDS ))
while [ "$(date +%s)" -lt "$end" ]; do write_call "$WORK/b.txt" || true; sleep 1; done
t_last_write=$(now)

log "3/5 DISASTER: kubectl delete namespace $NAMESPACE"
t_disaster=$(now)
kubectl delete namespace "$NAMESPACE" --wait=true --timeout=5m >/dev/null
t_gone=$(now)
log "    namespace gone after $(secs "$t_gone" "$t_disaster")s; API: $(curl -s -o /dev/null -w '%{http_code}' -m 3 "$BASE_URL/healthz" || true)"

log "4/5 restoring"
"$ROOT/scripts/restore.sh" 2>&1 | sed 's/^/  /'
t_restored=$(now)
new_server=$(kubectl -n "$NAMESPACE" get cluster call-router-db -o jsonpath='{.spec.plugins[0].parameters.serverName}')

log "5/5 verifying"
a_total=$(wc -l <"$WORK/a.txt"); a_ok=0
while read -r id _; do present "$id" && a_ok=$((a_ok + 1)); done <"$WORK/a.txt"
b_total=$(wc -l <"$WORK/b.txt"); b_ok=0; newest_ok=""; first_lost=""
while read -r id ts; do
  if present "$id"; then b_ok=$((b_ok + 1)); newest_ok="$ts"; else [ -z "$first_lost" ] && first_lost="$ts"; fi
done <"$WORK/b.txt"

rto=$(secs "$t_restored" "$t_disaster")
if [ -n "$newest_ok" ]; then
  rpo=$(secs "$t_last_write" "$(date -d "$newest_ok" +%s.%N)")
else
  rpo=$(secs "$t_last_write" "$t_backup")
fi
result=PASS; [ "$a_ok" -eq "$a_total" ] || result=FAIL

mkdir -p "$(dirname "$REPORT")"
cat >"$REPORT" <<MD
# DR drill $(date '+%Y-%m-%d %H:%M %Z')

Scenario: the whole \`$NAMESPACE\` namespace is deleted (PostgreSQL primary + replica
and their volumes, app, Secrets, alert rules). Restore from the S3 backup store.

| Step | Time ($(date +%Z)) |
|---|---|
| Base backup + WAL flush finished | $(hms "$t_backup") |
| Last write before the disaster | $(hms "$t_last_write") |
| Disaster: \`kubectl delete namespace $NAMESPACE\` | $(hms "$t_disaster") |
| Namespace fully gone | $(hms "$t_gone") |
| DB restored, app deployed, smoke test passed | $(hms "$t_restored") |

| Result | Value |
|---|---|
| Restored from backup folder | \`$old_server\` → new cluster archives to \`$new_server\` |
| Set A (written before the backup) | **$a_ok / $a_total** recovered |
| Set B (1/s for ${TRICKLE_SECONDS}s after the backup) | **$b_ok / $b_total** recovered${first_lost:+ (first lost call created at $first_lost)} |
| **RPO** (last write → newest recovered call) | **${rpo}s** |
| **RTO** (disaster → smoke test passing) | **${rto}s** |
| Verdict | **$result** |

RPO comes from WAL archiving (\`archive_timeout: 60s\`); calls after the last archived WAL
segment are lost. RTO includes deleting the namespace, a new PostgreSQL cluster
replaying the base backup and WAL, and a full \`helm --atomic\` deploy of the app.
MD
log "report: $REPORT"
log "set A $a_ok/$a_total, set B $b_ok/$b_total, RPO ${rpo}s, RTO ${rto}s -> $result"
rm -rf "$WORK"
[ "$result" = PASS ]
