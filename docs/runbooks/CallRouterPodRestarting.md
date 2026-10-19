# CallRouterPodRestarting

> **Placeholder runbook.** The full incident-response process (roles, comms, postmortem template) is added in a later step.

| | |
|---|---|
| Severity | `ticket` |
| Source | [`slo/call-router-slo.rules.yml`](../../slo/call-router-slo.rules.yml) |
| Dashboard | [call-router](http://localhost:3000/d/call-router/call-router) |

## What it means
A call-router container restarted more than 3 times in 15 minutes.

## Impact
Reduced capacity, and possibly dropped in-flight calls.

## First steps
1. `kubectl -n voice describe pod <pod>` → *Last State*: `OOMKilled` (raise memory limit), `Error` (check logs with `--previous`), or a failing liveness probe.

```bash
kubectl -n voice get pods -o wide
kubectl -n voice describe deploy/call-router
kubectl -n voice logs -l app.kubernetes.io/name=call-router --tail=100 | grep -E '"status":5|error'
helm -n voice history call-router
```

## Escalation
If it isn't mitigated within 30 minutes (page) or 2 working days (ticket), escalate to the voice-platform on-call lead.
