# CallRouterPodRestarting

| | |
|---|---|
| Severity | `ticket` (fix in working hours) |
| Alert rule | [`slo/call-router-slo.rules.yml`](../../slo/call-router-slo.rules.yml) |
| Dashboard | [Grafana: call-router](http://localhost:3000/d/call-router/call-router) (`make grafana`) |
| Escalation & roles | [docs/incident-response.md](../incident-response.md) |

## What it means
A call-router container restarted **more than 3 times in 15 minutes** (crash loop, OOM kill, or failing liveness probe).

## Impact
Usually little, because the other replica serves and readiness keeps traffic away from a restarting pod. But capacity is reduced, and if every pod is affected it becomes `CallRouterDown`.

## Symptoms
- *Pod restarts (1h)* panel climbing.
- `kubectl get pods` shows `CrashLoopBackOff` or a high RESTARTS count.

## Dashboards and queries
```bash
kubectl -n voice get pods -o wide
kubectl -n voice describe pod <pod> | sed -n '/Last State/,/Ready/p'   # reason + exit code
kubectl -n voice logs <pod> --previous --tail=100                        # logs of the crashed run
```
```promql
increase(kube_pod_container_status_restarts_total{container="call-router"}[15m])
kube_pod_container_status_last_terminated_reason{container="call-router"}
container_memory_working_set_bytes{container="call-router"}
```

## Diagnosis
1. **Exit reason** (`describe pod` → *Last State*):
   - `OOMKilled` (exit 137): memory limit hit. A known trap with the BEAM is that it sizes tables from the open-file limit (`ERL_MAX_PORTS`; this crash-looped the pods on kind in step 3, see the comment in `templates/configmap.yaml`). Compare `container_memory_working_set_bytes` with the limit.
   - `Error` (exit 1): the app failed at boot. Read `--previous` logs; `Ecto.Migrator` / `connection refused` errors mean the database is unreachable at startup.
   - Liveness probe failures (Events: `Liveness probe failed`): the BEAM is overloaded or stuck; check `vm_run_queue_total`.
2. **Since when?** Correlate with `helm history` (new image or config?) and node events.

## Mitigation
- Bad release: `helm -n voice rollback call-router`.
- OOM: raise `resources.limits.memory` or fix the leak; make sure `ERL_MAX_PORTS` is set (ConfigMap).
- DB at boot: fix the database first; pods recover on their own (backoff up to 5 min, or `kubectl delete pod` to retry immediately).

## Escalation
- No page: create a ticket in the voice-platform queue, fix within 2 working days.
- If it turns into user impact (a paging alert fires), handle it as an incident ([incident response](../incident-response.md)).

## Verification (when is it over?)
- Restart counter stops increasing for 15 minutes; pods `Running` and `Ready`.
