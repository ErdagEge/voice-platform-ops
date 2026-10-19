# CallRouterLatencyBudgetBurnMedium

> **Placeholder runbook.** The full incident-response process (roles, comms, postmortem template) is added in a later step.

| | |
|---|---|
| Severity | `page` |
| Source | [`slo/call-router-slo.rules.yml`](../../slo/call-router-slo.rules.yml) |
| Dashboard | [call-router](http://localhost:3000/d/call-router/call-router) |

## What it means
More than 6% of API requests have been slower than 500 ms over both 6h and 30m.

## Impact
Sustained slowness.

## First steps
1. Compare latency `by (pod)`, look for noisy neighbours or throttling.
2. Look at slow traces in Tempo (filter duration > 500ms).

```bash
kubectl -n voice get pods -o wide
kubectl -n voice describe deploy/call-router
kubectl -n voice logs -l app.kubernetes.io/name=call-router --tail=100 | grep -E '"status":5|error'
helm -n voice history call-router
```

## Escalation
If it isn't mitigated within 30 minutes (page) or 2 working days (ticket), escalate to the voice-platform on-call lead.
