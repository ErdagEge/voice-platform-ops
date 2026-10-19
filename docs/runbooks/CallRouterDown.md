# CallRouterDown

> **Placeholder runbook.** The full incident-response process (roles, comms, postmortem template) is added in a later step.

| | |
|---|---|
| Severity | `page` |
| Source | [`slo/call-router-slo.rules.yml`](../../slo/call-router-slo.rules.yml) |
| Dashboard | [call-router](http://localhost:3000/d/call-router/call-router) |

## What it means
Prometheus has had no healthy call-router scrape target for 2 minutes.

## Impact
Probably a total outage. All calls fail.

## First steps
1. `kubectl -n voice get deploy,pods,endpoints`: were replicas scaled to 0, or are pods crash-looping?
2. If the pods are healthy, check the ServiceMonitor or the Prometheus target page (scraping problem, not an outage).
3. Restore: `kubectl -n voice scale deploy/call-router --replicas=2` or `helm rollback`.

```bash
kubectl -n voice get pods -o wide
kubectl -n voice describe deploy/call-router
kubectl -n voice logs -l app.kubernetes.io/name=call-router --tail=100 | grep -E '"status":5|error'
helm -n voice history call-router
```

## Escalation
If it isn't mitigated within 30 minutes (page) or 2 working days (ticket), escalate to the voice-platform on-call lead.
