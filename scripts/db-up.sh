#!/usr/bin/env bash
# Create or upgrade the PostgreSQL cluster (Helm chart deploy/helm/call-router-db).
#
#   scripts/db-up.sh                          # new empty cluster, or upgrade the existing one
#   scripts/db-up.sh --restore-from latest    # NEW cluster restored from the newest backup
#   scripts/db-up.sh --restore-from <server>  # ... from a specific backup folder
#   scripts/db-up.sh --restore-from latest --target-time "2026-10-20 18:30:00+00"   # PITR
#
# Env: NAMESPACE [voice], VALUES [deploy/helm/call-router-db/values-local.yaml],
#      DB_TIMEOUT [10m]
#
# Backup folders ("serverName"): each new cluster archives to its own folder
# call-router-db-<UTC timestamp>, because a restored cluster starts a new
# timeline and must not write into the history it was restored from.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
NAMESPACE="${NAMESPACE:-voice}"
CLUSTER=call-router-db
CHART="$ROOT/deploy/helm/call-router-db"
VALUES="${VALUES:-$CHART/values-local.yaml}"
DB_TIMEOUT="${DB_TIMEOUT:-10m}"
log() { printf '[db-up] %s %s\n' "$(date +%T)" "$*"; }

restore_from="" target_time=""
while [ $# -gt 0 ]; do
  case "$1" in
    --restore-from) restore_from="$2"; shift 2 ;;
    --target-time) target_time="$2"; shift 2 ;;
    *) echo "unknown argument: $1" >&2; exit 2 ;;
  esac
done

# Newest backup folder in the object store = the one whose latest base
# backup (folders named like 20261020T182632) sorts last. Read through the
# SeaweedFS filer API inside its pod, so no S3 client is needed here.
s3_dirs() {
  kubectl -n backup exec deploy/seaweedfs -- wget -qO- --header 'Accept: application/json' "http://localhost:8888/buckets/backups/cnpg/$1" 2>/dev/null \
    | grep -o '"FullPath": *"[^"]*"' | sed -E 's/.*"([^"]*)"$/\1/' | xargs -rn1 basename
}
latest_server() {
  local best="" best_ts="" server ts
  for server in $(s3_dirs ""); do
    ts=$(s3_dirs "$server/base/" | sort | tail -1)
    if [ -n "$ts" ] && [[ "$ts" > "$best_ts" ]]; then best="$server" best_ts="$ts"; fi
  done
  [ -n "$best" ] || { echo "no base backup found in s3://backups/cnpg/" >&2; return 1; }
  echo "$best"
}

args=(-f "$VALUES")
current=$(kubectl -n "$NAMESPACE" get cluster "$CLUSTER" \
  -o jsonpath='{.spec.plugins[0].parameters.serverName}' 2>/dev/null || true)

if [ -n "$restore_from" ]; then
  if kubectl -n "$NAMESPACE" get cluster "$CLUSTER" >/dev/null 2>&1; then
    echo "cluster $CLUSTER already exists in $NAMESPACE - a restore needs it gone first" >&2
    echo "(make db-down, or the DR drill deletes the namespace)" >&2
    exit 1
  fi
  [ "$restore_from" = latest ] && restore_from=$(latest_server)
  log "restoring from backup folder: $restore_from ${target_time:+(PITR target $target_time)}"
  args+=(--set recovery.enabled=true --set "recovery.sourceServerName=$restore_from")
  [ -n "$target_time" ] && args+=(--set-string "recovery.targetTime=$target_time")
  current=""
fi

server="${current:-$CLUSTER-$(date -u +%Y%m%dT%H%M%S)}"
log "WAL/backups go to folder: $server"
args+=(--set "backup.serverName=$server")

"$ROOT/scripts/backup-store-up.sh" "$NAMESPACE" >/dev/null
# A restore needs the recovery settings again on later upgrades, or Helm
# would remove them; --reuse-values keeps whatever the cluster was created with.
if [ -z "$restore_from" ] && [ -n "$current" ]; then args+=(--reuse-values); fi
helm upgrade --install "$CLUSTER" "$CHART" -n "$NAMESPACE" --create-namespace "${args[@]}" >/dev/null
log "waiting for cluster Ready (timeout $DB_TIMEOUT) ..."
# The Cluster object may take a moment to get a status.
for _ in $(seq 1 30); do kubectl -n "$NAMESPACE" get cluster "$CLUSTER" >/dev/null 2>&1 && break; sleep 2; done
kubectl -n "$NAMESPACE" wait --for=condition=Ready "cluster/$CLUSTER" --timeout="$DB_TIMEOUT" >/dev/null
log "cluster $CLUSTER ready: $(kubectl -n "$NAMESPACE" get cluster "$CLUSTER" -o jsonpath='{.status.phase}'), primary $(kubectl -n "$NAMESPACE" get cluster "$CLUSTER" -o jsonpath='{.status.currentPrimary}')"
