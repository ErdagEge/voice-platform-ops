#!/usr/bin/env bash
# Take an on-demand PostgreSQL base backup to the object store, and make
# sure every change made until now is archived (WAL switch + wait).
#
#   scripts/backup.sh             # NAMESPACE [voice]
#
# Scheduled backups run hourly anyway (ScheduledBackup); WAL is archived
# continuously. Use this before risky changes or in the DR drill.
set -euo pipefail
NAMESPACE="${NAMESPACE:-voice}"
CLUSTER=call-router-db
BACKUP_TIMEOUT="${BACKUP_TIMEOUT:-600}"
log() { printf '[backup] %s %s\n' "$(date +%T)" "$*"; }

name="$CLUSTER-manual-$(date -u +%Y%m%d%H%M%S)"
log "creating Backup $name"
kubectl -n "$NAMESPACE" apply -f - >/dev/null <<YAML
apiVersion: postgresql.cnpg.io/v1
kind: Backup
metadata:
  name: $name
spec:
  cluster:
    name: $CLUSTER
  method: plugin
  pluginConfiguration:
    name: barman-cloud.cloudnative-pg.io
YAML

phase=""
for _ in $(seq 1 "$BACKUP_TIMEOUT"); do
  phase=$(kubectl -n "$NAMESPACE" get backup "$name" -o jsonpath='{.status.phase}' 2>/dev/null || true)
  case "$phase" in
    completed) break ;;
    failed) log "FAILED: $(kubectl -n "$NAMESPACE" get backup "$name" -o jsonpath='{.status.error}')"; exit 1 ;;
  esac
  sleep 1
done
[ "$phase" = completed ] || { log "timed out (phase: ${phase:-none})"; exit 1; }
log "base backup completed: $(kubectl -n "$NAMESPACE" get backup "$name" -o jsonpath='{.status.backupId} (WAL {.status.beginWal} .. {.status.endWal})')"

# Close the current WAL segment and wait until the archiver has shipped it:
# from now on, everything committed before this point is recoverable.
primary=$(kubectl -n "$NAMESPACE" get cluster "$CLUSTER" -o jsonpath='{.status.currentPrimary}')
psql() { kubectl -n "$NAMESPACE" exec "$primary" -c postgres -- psql -qtAX -d app -c "$1"; }
# "- 1": if nothing was written since the last switch, pg_switch_wal()
# returns the exact start of the (empty) next segment; the byte before it
# is in the last segment that must be archived.
wal=$(psql "SELECT pg_walfile_name(pg_switch_wal() - 1)")
for _ in $(seq 1 120); do
  archived=$(psql "SELECT coalesce(last_archived_wal, '') FROM pg_stat_archiver")
  if [[ ! "$archived" < "$wal" ]]; then
    log "WAL archived up to $archived - everything until $(date +%T) is recoverable"
    exit 0
  fi
  sleep 1
done
log "WARNING: WAL $wal not archived after 120 s (check CallRouterWALArchivingFailing)"
exit 1
