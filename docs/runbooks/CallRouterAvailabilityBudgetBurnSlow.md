# CallRouterAvailabilityBudgetBurnSlow

> **Placeholder runbook.** The full incident-response process (roles, comms, postmortem template) is added in a later step.

| | |
|---|---|
| Severity | `ticket` |
| Source | [`slo/call-router-slo.rules.yml`](../../slo/call-router-slo.rules.yml) |
| Dashboard | [call-router](http://localhost:3000/d/call-router/call-router) |

## What it means
More than 0.5% of API requests (1x budget) have failed over both 3 days and 6 hours. At this pace the SLO will be missed this month.

## Impact
Low-grade, persistent error leak. Not urgent, but it needs an owner.

## First steps
1. Break errors down by route and status in Grafana.
2. Open a ticket. Prioritise reliability work over features until the budget recovers.

```bash
kubectl -n voice get pods -o wide
kubectl -n voice describe deploy/call-router
kubectl -n voice logs -l app.kubernetes.io/name=call-router --tail=100 | grep -E '"status":5|error'
helm -n voice history call-router
```

## Escalation
If it isn't mitigated within 30 minutes (page) or 2 working days (ticket), escalate to the voice-platform on-call lead.
