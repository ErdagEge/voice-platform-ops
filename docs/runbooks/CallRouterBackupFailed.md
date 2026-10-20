# CallRouterBackupFailed

| | |
|---|---|
| Severity | `ticket` (fix in working hours) |
| Alert rule | [`slo/call-router-reliability.rules.yml`](../../slo/call-router-reliability.rules.yml) |
| Dashboard | [Grafana: call-router](http://localhost:3000/d/call-router/call-router) (`make grafana`) |
| Escalation & roles | [docs/incident-response.md](../incident-response.md) |

## What it means
Either **the latest base backup failed** (`CallRouterBackupFailed`) or **no base backup has succeeded for over 2h10m** (`CallRouterBackupTooOld`; backups are hourly). Both alerts share this runbook.

## Impact
None right now, as long as WAL archiving still works. A restore then replays more WAL starting from an older base backup, so it's slower (RTO goes up). If WAL archiving is *also* broken, see [CallRouterWALArchivingFailing](CallRouterWALArchivingFailing.md); that one is urgent.

## Symptoms
- `kubectl -n voice get backups` shows `failed`, or the newest `completed` backup is old.
- Cluster condition `LastBackupSucceeded=False`.

## Dashboards and queries
```bash
kubectl -n voice get scheduledbackup,backups --sort-by=.metadata.creationTimestamp | tail -5
kubectl -n voice get backup <name> -o jsonpath='{.status.phase} {.status.error}{"\n"}'
kubectl -n voice logs <primary> -c plugin-barman-cloud --tail=100
kubectl -n cnpg-system logs deploy/barman-cloud-plugin-barman-cloud --tail=50
```
```promql
time() - barman_cloud_cloudnative_pg_io_last_available_backup_timestamp
barman_cloud_cloudnative_pg_io_last_failed_backup_timestamp
```

## Diagnosis
1. **Failed backups:** read `status.error`. Common causes: the object store is unreachable or rejects the credentials (same checks as [WAL archiving](CallRouterWALArchivingFailing.md)), or the store is full.
2. **No backups at all:** is the ScheduledBackup suspended (`spec.suspend`) or deleted? Is the barman-cloud plugin pod running? After a restore, check the new cluster has its ScheduledBackup (`helm -n voice get manifest call-router-db`).
3. **Retention:** the ObjectStore keeps 7 days; if backups are deleted too early, check `retentionPolicy`.

## Mitigation
- Fix the cause, then take a backup immediately: `scripts/backup.sh` (it also confirms WAL archiving).
- Resume a suspended schedule: `kubectl -n voice patch scheduledbackup call-router-db-hourly --type merge -p '{"spec":{"suspend":false}}'`.
- If backups were broken for a long time, run a **restore test** afterwards (`scripts/dr-drill.sh` on a scratch cluster). A backup only counts once you've restored from it.

## Escalation
- No page: create a ticket in the voice-platform queue, fix within 2 working days.
- If it turns into user impact (a paging alert fires), handle it as an incident ([incident response](../incident-response.md)).

## Verification (when is it over?)
- A new `completed` Backup; `LastBackupSucceeded=True`; both alerts resolved.
- Optional: `scripts/dr-drill.sh` passes.
