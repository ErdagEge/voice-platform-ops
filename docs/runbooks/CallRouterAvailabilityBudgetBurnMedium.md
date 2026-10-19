# CallRouterAvailabilityBudgetBurnMedium

> **Placeholder runbook.** The full incident-response process (roles, comms, postmortem template) is added in a later step.

| | |
|---|---|
| Severity | `page` |
| Source | [`slo/call-router-slo.rules.yml`](../../slo/call-router-slo.rules.yml) |
| Dashboard | [call-router](http://localhost:3000/d/call-router/call-router) |

## What it means
More than 3% of API requests (6x budget) have failed over both 6h and 30m. That spends 5% of the monthly error budget every 6 hours.

## Impact
Partial or intermittent failure. Users are noticing.

## First steps
1. Look for a single bad pod or node: error rate `by (pod)`.
2. Check recent config changes and node events (`kubectl get events -n voice`).
3. If one pod is affected, delete it so the Deployment replaces it.

```bash
kubectl -n voice get pods -o wide
kubectl -n voice describe deploy/call-router
kubectl -n voice logs -l app.kubernetes.io/name=call-router --tail=100 | grep -E '"status":5|error'
helm -n voice history call-router
```

## Escalation
If it isn't mitigated within 30 minutes (page) or 2 working days (ticket), escalate to the voice-platform on-call lead.
