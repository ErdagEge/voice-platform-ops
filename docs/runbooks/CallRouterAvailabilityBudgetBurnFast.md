# CallRouterAvailabilityBudgetBurnFast

> **Placeholder runbook.** The full incident-response process (roles, comms, postmortem template) is added in a later step.

| | |
|---|---|
| Severity | `page` |
| Source | [`slo/call-router-slo.rules.yml`](../../slo/call-router-slo.rules.yml) |
| Dashboard | [call-router](http://localhost:3000/d/call-router/call-router) |

## What it means
More than 7.2% of API requests (14.4x the 0.5% error budget) have failed over both the last hour and the last 5 minutes. At this rate, 2% of the 30-day error budget is gone every hour.

## Impact
Callers can't be routed. Act now.

## First steps
1. Was there a deploy in the last hour? Run `helm -n voice history call-router`. If so, roll back with `helm -n voice rollback call-router`.
2. Check the error-rate panel and `call_router_errors_total` by `kind`. `injected` means fault injection is on: set `config.faultErrorRate` to 0.
3. Open a failing request's trace from the logs (`trace_id`) in Grafana → Explore → Tempo.

```bash
kubectl -n voice get pods -o wide
kubectl -n voice describe deploy/call-router
kubectl -n voice logs -l app.kubernetes.io/name=call-router --tail=100 | grep -E '"status":5|error'
helm -n voice history call-router
```

## Escalation
If it isn't mitigated within 30 minutes (page) or 2 working days (ticket), escalate to the voice-platform on-call lead.
