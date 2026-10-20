# CallRouterLatencyBudgetBurnMedium

| | |
|---|---|
| Severity | `page` (wake someone up) |
| Alert rule | [`slo/call-router-slo.rules.yml`](../../slo/call-router-slo.rules.yml) |
| Dashboard | [Grafana: call-router](http://localhost:3000/d/call-router/call-router) (`make grafana`) |
| Escalation & roles | [docs/incident-response.md](../incident-response.md) |

## What it means
More than the allowed 1 % of API requests take longer than **500 ms**: the latency error budget burns **6x** too fast over 6h and 30m (for 15m).

## Impact
Calls still succeed but slowly; in telephony a slow routing decision means dead air for the caller or a timeout at the SIP/telephony side, which then fails the call anyway.

## Symptoms
- *API latency p50/p95/p99* panel: p99 above 0.5 s.
- *Latency error budget remaining* dropping.
- Error rate usually normal (that is why latency has its own SLO).

## Dashboards and queries
```promql
# share of API requests slower than 500 ms (SLI)
slo:sli_error:ratio_rate5m{slo="call-router-latency"}
# p95 / p99 per route
histogram_quantile(0.99, sum by (le, route) (rate(http_request_duration_seconds_bucket{job="call-router"}[5m])))
# is the database slow?  (statement time per call)
rate(cnpg_pg_stat_database_blk_read_time{datname="app"}[5m])
```
Open a slow trace: Grafana → Explore → Tempo → `{ resource.service.name = "call-router" && duration > 500ms }`. The span waterfall shows whether `call_store.put` (the database) or the handler itself is slow.

## Diagnosis
1. **Which route is slow?** Look at the p99-by-route query, and check whether all pods or just one are slow.
2. **Where is the time spent?** Open a slow trace (above). If `call_store.put` is long, the database is slow; if the server span is long but its children are short, the app itself (CPU) is slow.
3. **Saturation?** `vm_run_queue_total` > 0 for a long time, or pods at their CPU limit (`container_cpu_cfs_throttled_seconds_total`), means it needs more replicas or CPU.
4. **Injected?** `helm -n voice get values call-router | grep -i fault`. `faultLatencyMs` > 0 adds delay on purpose (chaos experiment 06).
5. **Recent change?** `helm -n voice history call-router`.

## Mitigation
- **Slow DB:** check [CallRouterDatabaseDown](CallRouterDatabaseDown.md) diagnosis (replica lag, failover in progress, disk). A CNPG switchover to a healthy instance: `kubectl cnpg promote call-router-db <instance>` (cnpg kubectl plugin) or delete a sick primary pod.
- **CPU saturation:** `kubectl -n voice scale deploy/call-router --replicas=4`.
- **Bad deploy:** `helm -n voice rollback call-router`.
- **Latency injection left on:** `--reuse-values --set config.faultLatencyMs=0`.

## Escalation
- **0-15 min:** the on-call engineer acknowledges, opens an incident channel and takes the Incident Commander role ([incident response](../incident-response.md)).
- **15 min, not mitigated:** page the secondary on-call / voice-platform lead.
- **30 min, customer impact ongoing:** declare SEV1, involve the Communications Lead for customer updates.
- Database or data loss suspected: involve the database owner immediately.

## Verification (when is it over?)
- `slo:sli_error:ratio_rate5m{slo="call-router-latency"}` below 0.01 and p99 below 500 ms.
- The alert clears after the short window is clean; record the budget spent.

## Related
Verified in [chaos experiment 06](../../chaos/results/06-latency.md).
