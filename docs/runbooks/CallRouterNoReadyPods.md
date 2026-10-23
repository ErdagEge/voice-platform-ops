# CallRouterNoReadyPods

| | |
|---|---|
| Severity | `page` (wake someone up) |
| Alert rule | [`slo/call-router-reliability.rules.yml`](../../slo/call-router-reliability.rules.yml) |
| Dashboard | [Grafana: call-router](http://localhost:3000/d/call-router/call-router) (`make grafana`) |
| Escalation & roles | [docs/incident-response.md](../incident-response.md) |
| Added by | [postmortem 2026-10-20 database outage](../postmortems/2026-10-20-database-outage.md), action item 1 |

## What it means
The `call-router` Deployment wants ≥ 1 pod but **none has been Ready for 1 minute**
(`kube_deployment_status_replicas_ready == 0`, from kube-state-metrics).

## Impact
**Full outage of the API.** The Service has no endpoints, so callers get *connection
refused / timeout* and the request never reaches the app. That is why the availability
SLO alerts (built from the app's own request metrics) stay quiet in this situation -
this alert covers that blind spot, whatever the cause.

## Symptoms
- `kubectl -n voice get deploy call-router` shows `0/2` READY.
- Pods are `0/1 Running` (alive, readiness failing) or `CrashLoopBackOff` / `Pending`.
- `curl localhost:8080/healthz` fails with connection refused.

## Dashboards and queries
```bash
kubectl -n voice get deploy,pods -l app.kubernetes.io/name=call-router -o wide
kubectl -n voice describe pod <pod> | sed -n '/Conditions/,/Events/p;/Events/,$p'
kubectl -n voice logs <pod> --tail=50
kubectl -n voice port-forward pod/<pod> 4000:4000 & curl -s localhost:4000/readyz   # why not ready?
```
```promql
kube_deployment_status_replicas_ready{deployment="call-router"}
call_router_db_up                       # 0 = readiness fails because of the database
kube_pod_container_status_waiting_reason{namespace="voice"}
```

## Diagnosis
Find *why* readiness fails - the alert only says *that* it fails:
1. **`call_router_db_up == 0`** → the database is the cause; `CallRouterDatabaseDown` fires too. Follow [that runbook](CallRouterDatabaseDown.md).
2. **Pods `CrashLoopBackOff`** → the app crashes at boot (bad config, a migration failing, the DB unreachable at start-up). Read `kubectl logs --previous`.
3. **Pods `Pending`** → no node can take them (capacity, topology spread, node failure). `kubectl describe pod` → Events.
4. **Pods Ready on and off** → probe too strict or app overloaded; check CPU throttling and the latency panels.
5. **Just after a deploy** → a broken release that `--atomic` did not catch; roll back.

## Mitigation
- Bad release: `helm -n voice rollback call-router` (or `scripts/rollback-demo.sh` shows how).
- Database: see [CallRouterDatabaseDown](CallRouterDatabaseDown.md).
- Node just restarted and logs show `nxdomain` for `call-router-db-rw` (seen in [chaos experiment 03](../../chaos/results/03-node-failure.md)): the app retries migrations in-process and should become Ready on its own once kube-proxy/CoreDNS answers. If it is still not Ready after a few minutes, check `kube-proxy` on that node (`kubectl -n kube-system get pods -o wide | grep <node>`) and delete that pod if it is unhealthy (the DaemonSet recreates it). Deleting the app pod is only needed if it is still `CrashLoopBackOff` from an image built before the retry.
- Capacity / nodes: uncordon or add nodes; temporarily relax the hard topology spread (`topologySpread.hostname.whenUnsatisfiable=ScheduleAnyway`) if one node is left.

## Escalation
- **0-15 min:** on-call acknowledges, becomes Incident Commander ([incident response](../incident-response.md)), SEV1 by default (full outage).
- **15 min, not mitigated:** page the secondary on-call / voice-platform lead; Communications Lead posts a status update.

## Verification (when is it over?)
- `kubectl -n voice get deploy call-router` shows `2/2` READY and the alert resolves.
- `scripts/ci-smoke.sh` passes against the public URL.

## Related
[CallRouterDatabaseDown](CallRouterDatabaseDown.md) · [CallRouterDown](CallRouterDown.md) (no scrape target at all) · [chaos experiment 05](../../chaos/results/05-db-down-fence.md)
