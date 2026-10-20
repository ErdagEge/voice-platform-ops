# Chaos experiment: 01-pod-kill-force

Run: 2026-10-20 20:48 CEST on kind (3 nodes), 2 app replicas, PostgreSQL primary + replica.

## Hypothesis
Killing one of two replicas (force) under load causes at most 1% failed requests, a replacement pod is Ready within 60 s, no stored call is lost, and no SLO alert fires.

## Method
4 workers sending POST /api/calls + GET for 60s through the NodePort. At t=15s: `kubectl delete pod call-router-6b945bd8db-lmx78 --grace-period=0 --force`. Afterwards every created call id is read back.

## Result
- Requests: `total=24978 ok=24978 errors=0 error_pct=0.00 err_window_s=0.0 first_err_ms=0 last_err_ms=0`
- Error codes: `` (000 = connection refused/reset/timeout)
- Replacement Ready after: **6s**
- Alerts pending/firing after the run (checked by hand at 20:53 CEST): `none`
- Calls lost: **0** of 12489
- Pods after: call-router-6b945bd8db-lzq7x on voice-platform-worker2; call-router-6b945bd8db-n6dw9 on voice-platform-worker; 

## Verdict
PASS - hypothesis held.
