# CallRouterLatencyBudgetBurnFast

> **Placeholder runbook.** The full incident-response process (roles, comms, postmortem template) is added in a later step.

| | |
|---|---|
| Severity | `page` |
| Source | [`slo/call-router-slo.rules.yml`](../../slo/call-router-slo.rules.yml) |
| Dashboard | [call-router](http://localhost:3000/d/call-router/call-router) |

## What it means
More than 14.4% of API requests took longer than 500 ms over both 1h and 5m (latency SLO: 99% < 500 ms).

## Impact
Calls connect slowly or time out in the telephony layer.

## First steps
1. Check p95/p99 panels and CPU throttling (`container_cpu_cfs_throttled_periods_total`).
2. Check `FAULT_LATENCY_MS` (fault injection) and recent deploys.
3. Scale out: `kubectl -n voice scale deploy/call-router --replicas=4`, or let the HPA do it.

```bash
kubectl -n voice get pods -o wide
kubectl -n voice describe deploy/call-router
kubectl -n voice logs -l app.kubernetes.io/name=call-router --tail=100 | grep -E '"status":5|error'
helm -n voice history call-router
```

## Escalation
If it isn't mitigated within 30 minutes (page) or 2 working days (ticket), escalate to the voice-platform on-call lead.
