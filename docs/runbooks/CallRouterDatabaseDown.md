# CallRouterDatabaseDown

| | |
|---|---|
| Severity | `page` (wake someone up) |
| Alert rule | [`slo/call-router-reliability.rules.yml`](../../slo/call-router-reliability.rules.yml) |
| Dashboard | [Grafana: call-router](http://localhost:3000/d/call-router/call-router) (`make grafana`) |
| Escalation & roles | [docs/incident-response.md](../incident-response.md) |

## What it means
Every call-router pod reports `call_router_db_up == 0` for 1 minute: **no pod can query PostgreSQL**.

## Impact
**Full outage of the API.** Readiness depends on the database, so Kubernetes has removed all pods from the Service. Callers get connection errors (not HTTP 5xx), so the availability SLO alerts, which are based on the app's own metrics, **do not see this**. This alert is the one that pages. Data already stored is safe on the database volumes and in the backups.

## Symptoms
- `curl localhost:8080/api/calls` → connection refused; `/readyz` on a pod returns 503 `not_ready`.
- `kubectl get pods` shows app pods `0/1 Running` (alive but not Ready), *not* restarting.
- Logs: `database unavailable: ... connection not available` / `tcp connect ... refused`.

## Dashboards and queries
```bash
kubectl -n voice get cluster call-router-db              # phase, ready instances, current primary
kubectl -n voice get pods -l cnpg.io/cluster=call-router-db -o wide
kubectl -n voice describe cluster call-router-db | sed -n '/Conditions/,$p'
kubectl -n voice logs <db-pod> -c postgres --tail=50
kubectl -n voice get cluster call-router-db -o jsonpath='{.metadata.annotations}'   # hibernation?
```
```promql
call_router_db_up
cnpg_collector_up{cluster="call-router-db"}
cnpg_pg_replication_streaming_replicas
```

## Diagnosis
1. **Is PostgreSQL running at all?** No DB pods: check whether the cluster was hibernated (`cnpg.io/hibernation=on` annotation), deleted, or whether the nodes are gone. Pods running but `postgres` not ready: check for a `cnpg.io/fencedInstances` annotation (instances deliberately stopped).
2. **Pods there but not Ready?** Read the `postgres` container logs: is the disk full (`No space left on device`), is a failover in progress, or is it crash recovery (replaying WAL)?
3. **Pods healthy but the app can't connect?** Check the `call-router-db-rw` Service has an endpoint, and that the `call-router-db-app` Secret is unchanged (password rotated?).
4. **Failover stuck?** `kubectl -n voice get cluster call-router-db -o jsonpath='{.status.phase}'` shows *Failing over* for > 1 min: look at the operator logs (`kubectl -n cnpg-system logs deploy/cnpg-cloudnative-pg`).

## Mitigation
- **Hibernated:** `kubectl -n voice annotate cluster call-router-db --overwrite cnpg.io/hibernation=off`.
- **Fenced** (`cnpg.io/fencedInstances` annotation present - someone stopped PostgreSQL for maintenance or forensics): confirm with whoever set it, then `kubectl -n voice annotate cluster call-router-db cnpg.io/fencedInstances-`.
- **Primary dead, replica healthy:** CNPG fails over automatically within seconds; if not, promote manually with `kubectl cnpg promote call-router-db call-router-db-2`.
- **Disk full:** increase `storage.size` (online resize where the storage class supports it), or delete WAL that is already archived (only on CNPG's advice; never by hand).
- **Database lost** (volumes gone or corrupt): restore from backup with `make db-down && scripts/restore.sh` ([DR](../dr.md)). Decide with the IC: a restore loses up to RPO (about 1 minute) of data.
- The app needs **no action**: it reconnects, readiness turns green, and traffic flows again within about 10 s.

## Escalation
- **0-15 min:** the on-call engineer acknowledges, opens an incident channel and takes the Incident Commander role ([incident response](../incident-response.md)).
- **15 min, not mitigated:** page the secondary on-call / voice-platform lead.
- **30 min, customer impact ongoing:** declare SEV1, involve the Communications Lead for customer updates.
- Database or data loss suspected: involve the database owner immediately.

## Verification (when is it over?)
- `call_router_db_up == 1` on all pods, `kubectl -n voice get deploy call-router` shows 2/2 ready.
- `scripts/ci-smoke.sh` passes; `CallRouterDatabaseNoReplica` is not firing (HA restored).
- Check that no acknowledged call was lost: compare `SELECT count(*) FROM calls` before/after if a restore happened.

## Related
This exact alert fired in [chaos experiment 05](../../chaos/results/05-db-down-fence.md) → [postmortem](../postmortems/2026-10-20-database-outage.md).
