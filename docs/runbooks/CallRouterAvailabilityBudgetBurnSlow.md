# CallRouterAvailabilityBudgetBurnSlow

| | |
|---|---|
| Severity | `ticket` (fix in working hours) |
| Alert rule | [`slo/call-router-slo.rules.yml`](../../slo/call-router-slo.rules.yml) |
| Dashboard | [Grafana: call-router](http://localhost:3000/d/call-router/call-router) (`make grafana`) |
| Escalation & roles | [docs/incident-response.md](../incident-response.md) |

## What it means
More API requests fail (HTTP 5xx) than the availability SLO allows: the error budget is burning **1x** too fast over both the long and the short window (3d and 6h), for at least 1h. That is 10% of the budget in 3 days; the SLO will be missed at the end of the 30-day window if nothing changes.

## Impact
Callers' calls are not being routed. A small but constant error rate: no immediate harm, but it will cost the monthly SLO.

## Symptoms
- *Error rate* panel above the dashed SLO line; *Availability burn rate* above 1.
- `errors_total{kind=...}` rising on the *Errors by kind* panel.
- Possibly reports from support / telephony partners about failed call setups.

## Dashboards and queries
```promql
# share of failing API requests (SLI), 5m
slo:sli_error:ratio_rate5m{slo="call-router-availability"}
# burn rates (1 = exactly on budget)
slo:sli_error:ratio_rate1h{slo="call-router-availability"} / 0.005
# error budget left over 30 days (1 = untouched, <0 = SLO missed)
slo:error_budget_remaining:ratio{slo="call-router-availability"}
```
```bash
kubectl -n voice logs -l app.kubernetes.io/name=call-router --tail=200 | grep -E '"status":5|"level":"error"'
```
In Grafana, the **Logs** panel links every log line's `trace_id` to its trace in Tempo.

## Diagnosis
1. **Is it real?** Compare the error ratio panel with traffic. A handful of errors at very low traffic can look like a high ratio.
2. **Which route and status?** `sum by (route, status) (rate(http_requests_total{job="call-router",status=~"5.."}[5m]))`
3. **Why?** `sum by (kind) (rate(call_router_errors_total[5m]))`:
   - `storage`: the database is the problem. Check `call_router_db_up` and go to [CallRouterDatabaseDown](CallRouterDatabaseDown.md).
   - `injected`: fault injection is switched on (`config.faultErrorRate`). Check `helm -n voice get values call-router`.
   - `server`: application bug, so look at the logs (below) and the last deploy.
4. **Did something change?** `helm -n voice history call-router` and recent CI runs. A deploy within the last hour is the most likely cause.
5. **One pod or all?** `sum by (pod) (rate(http_requests_total{status=~"5.."}[5m]))`. A single bad pod can be deleted; Kubernetes recreates it.

## Mitigation
Mitigate first, find the root cause later:
- **Bad deploy:** `helm -n voice rollback call-router` (to the previous revision), then watch the error ratio.
- **Fault injection left on:** `helm upgrade ... --reuse-values --set config.faultErrorRate=0`.
- **Database:** follow [CallRouterDatabaseDown](CallRouterDatabaseDown.md).
- **One bad pod:** `kubectl -n voice delete pod <pod>`.
- **Overload:** scale out with `kubectl -n voice scale deploy/call-router --replicas=4` (or raise the HPA's minReplicas).

## Escalation
- No page: create a ticket in the voice-platform queue, fix within 2 working days.
- If it turns into user impact (a paging alert fires), handle it as an incident ([incident response](../incident-response.md)).

## Verification (when is it over?)
- `slo:sli_error:ratio_rate5m` back below 0.005 (0.5 %) and the 5m burn rate below 1.
- The alert resolves on its own once the short window (6h) is clean. That is the point of the short window.
- Note the budget spent (*SLO* row) in the incident ticket; if the budget is exhausted, freeze risky deploys ([SLO policy](../../README.md#observability--slos)).

## Related
Postmortem example: [2026-10-20 database outage](../postmortems/2026-10-20-database-outage.md).
