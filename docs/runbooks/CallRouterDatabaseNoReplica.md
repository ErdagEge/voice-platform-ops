# CallRouterDatabaseNoReplica

| | |
|---|---|
| Severity | `ticket` (fix in working hours) |
| Alert rule | [`slo/call-router-reliability.rules.yml`](../../slo/call-router-reliability.rules.yml) |
| Dashboard | [Grafana: call-router](http://localhost:3000/d/call-router/call-router) (`make grafana`) |
| Escalation & roles | [docs/incident-response.md](../incident-response.md) |

## What it means
The PostgreSQL primary has had **no streaming replica for 10 minutes**.

## Impact
None right now. But high availability is gone: if the primary fails next, there is no automatic failover. The service is down until it is restored from backup, and up to about 1 minute of data could be lost.

## Symptoms
- `kubectl -n voice get cluster` shows `1/2` ready instances.
- A DB pod `Pending` (often after a node drain, because its volume is node-local) or crash-looping.

## Dashboards and queries
```bash
kubectl -n voice get pods -l cnpg.io/cluster=call-router-db -o wide
kubectl -n voice describe pod <pending-db-pod> | tail -15   # scheduling reason
kubectl get nodes                                             # cordoned / NotReady node?
```
```promql
cnpg_pg_replication_streaming_replicas
cnpg_pg_replication_lag
```

## Diagnosis
1. **Pending replica?** It usually means the node holding its volume is cordoned or down, or (with required anti-affinity) there is no other free node.
2. **Replica crash-looping?** Read its logs: is it failing to stream from the primary, or is it missing WAL (it then fetches from the backup store)?
3. **Replication lag huge?** It may be re-syncing after a long outage; let it catch up.

## Mitigation
- Node cordoned after maintenance: `kubectl uncordon <node>`.
- Node gone for good: delete the replica's PVC and pod, so CNPG re-clones the replica onto a healthy node (`kubectl -n voice delete pvc <pvc> pod <pod>`).
- Make sure no other risky work (deploys, node maintenance) happens until HA is back.

## Escalation
- No page: create a ticket in the voice-platform queue, fix within 2 working days.
- If it turns into user impact (a paging alert fires), handle it as an incident ([incident response](../incident-response.md)).

## Verification (when is it over?)
- `cnpg_pg_replication_streaming_replicas >= 1` and the cluster shows 2/2 ready.

## Related
Seen during [chaos experiment 02 (node drain)](../../chaos/results/02-node-drain.md).
