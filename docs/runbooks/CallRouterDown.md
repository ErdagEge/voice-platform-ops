# CallRouterDown

| | |
|---|---|
| Severity | `page` (wake someone up) |
| Alert rule | [`slo/call-router-slo.rules.yml`](../../slo/call-router-slo.rules.yml) |
| Dashboard | [Grafana: call-router](http://localhost:3000/d/call-router/call-router) (`make grafana`) |
| Escalation & roles | [docs/incident-response.md](../incident-response.md) |

## What it means
Prometheus has had **no healthy call-router scrape target for 2 minutes**: no pod answers `/metrics`.

## Impact
Very likely a full outage: no pod is running, or none is reachable. (Less likely: only the scraping is broken and calls still work, so check this first.)

## Symptoms
- All panels on the dashboard go empty (*No data*).
- `curl http://localhost:8080/healthz` fails (kind) / load balancer health checks fail (GKE).

## Dashboards and queries
```bash
kubectl -n voice get deploy,rs,pods,endpoints -o wide
kubectl -n voice describe deploy/call-router | tail -20
kubectl -n voice get events --sort-by=.lastTimestamp | tail -20
helm -n voice history call-router
```
```promql
up{job="call-router"}
kube_deployment_status_replicas_available{deployment="call-router"}
```

## Diagnosis
1. **Do pods exist?** `kubectl -n voice get pods`. If there are 0, someone scaled to 0, or the Deployment or namespace was deleted. For the namespace, see the [DR runbook](../dr.md).
2. **Pending?** `kubectl describe pod` shows the scheduling reason: not enough resources, no node free for the hard topology spread, or a node is down.
3. **CrashLoopBackOff?** Go to [CallRouterPodRestarting](CallRouterPodRestarting.md). A database that is down at boot should leave the pod Running and NotReady (migrations retry), not restarting; if logs still show `Ecto.Migrator` crashing init, the image is from before that fix. Follow [CallRouterDatabaseDown](CallRouterDatabaseDown.md) either way.
4. **Running but not scraped?** Check *Prometheus → Status → Targets* (`make prometheus`). If the ServiceMonitor is missing, re-deploy the chart; if it's a network policy, check that.

## Mitigation
- Scaled to 0 / deleted: `make deploy` or `scripts/deploy.sh` (Helm reinstalls), or `helm -n voice rollback call-router`.
- Namespace gone: `scripts/restore.sh` (DB from backup + app), see [DR](../dr.md).
- Pending pods: free capacity or temporarily relax the spread: `--set topologySpread[0].whenUnsatisfiable=ScheduleAnyway`.

## Escalation
- **0-15 min:** the on-call engineer acknowledges, opens an incident channel and takes the Incident Commander role ([incident response](../incident-response.md)).
- **15 min, not mitigated:** page the secondary on-call / voice-platform lead.
- **30 min, customer impact ongoing:** declare SEV1, involve the Communications Lead for customer updates.
- Database or data loss suspected: involve the database owner immediately.

## Verification (when is it over?)
- `up{job="call-router"} == 1` for every pod; `make kind-smoke` / `scripts/ci-smoke.sh` passes.
- The availability burn alerts will show how much budget the outage cost.
