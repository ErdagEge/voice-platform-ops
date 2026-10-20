# CallRouterWALArchivingFailing

| | |
|---|---|
| Severity | `page` (wake someone up) |
| Alert rule | [`slo/call-router-reliability.rules.yml`](../../slo/call-router-reliability.rules.yml) |
| Dashboard | [Grafana: call-router](http://localhost:3000/d/call-router/call-router) (`make grafana`) |
| Escalation & roles | [docs/incident-response.md](../incident-response.md) |

## What it means
On the primary, **the newest WAL file could not be archived** to the backup store for 15 minutes.

## Impact
No user impact yet, but: (1) **point-in-time recovery can't go past the last archived WAL**, so RPO grows every minute, and (2) WAL that hasn't been archived is kept on disk, so the volume fills up and the database will eventually stop.

## Symptoms
- Cluster condition `ContinuousArchiving=False`.
- `cnpg_pg_stat_archiver_failed_count` increasing; `cnpg_collector_pg_wal_archive_status{value="ready"}` (WAL files waiting) growing.

## Dashboards and queries
```bash
kubectl -n voice get cluster call-router-db -o jsonpath='{range .status.conditions[*]}{.type}={.status} {.message}{"\n"}{end}'
kubectl -n voice logs <primary> -c plugin-barman-cloud --tail=50        # archiver sidecar errors
kubectl -n backup get pods; kubectl -n backup logs deploy/seaweedfs --tail=50
```
```promql
cnpg_pg_stat_archiver_seconds_since_last_archival
cnpg_collector_pg_wal_archive_status{value="ready"}
kubelet_volume_stats_used_bytes{persistentvolumeclaim=~"call-router-db-.*"} / kubelet_volume_stats_capacity_bytes
```

## Diagnosis
1. **Is the backup store up?** `kubectl -n backup get pods` (SeaweedFS on kind; on GKE: the GCS bucket and its IAM).
2. **Credentials?** `AccessDenied` / `SignatureDoesNotMatch` in the sidecar log means the `backup-s3-credentials` Secret is out of sync with the store. Re-run `scripts/backup-store-up.sh voice`.
3. **Network?** Check that the sidecar can reach `seaweedfs.backup.svc:8333` (DNS, NetworkPolicy).
4. **Store full?** Check disk use of the SeaweedFS PVC / bucket quota.

## Mitigation
- Fix the store / credentials; archiving retries on its own and catches up (the queued WAL files are shipped in order).
- If the disk is about to fill before that, increase the PVC size first (buys time).
- Once archiving works again, **take a fresh base backup** with `scripts/backup.sh`, so the restore chain is short and verified.

## Escalation
- **0-15 min:** the on-call engineer acknowledges, opens an incident channel and takes the Incident Commander role ([incident response](../incident-response.md)).
- **15 min, not mitigated:** page the secondary on-call / voice-platform lead.
- **30 min, customer impact ongoing:** declare SEV1, involve the Communications Lead for customer updates.
- Database or data loss suspected: involve the database owner immediately.

## Verification (when is it over?)
- Condition `ContinuousArchiving=True`, `cnpg_pg_stat_archiver_seconds_since_last_archival` < 120 s, WAL `ready` count back to ~0.
- `scripts/backup.sh` succeeds.
