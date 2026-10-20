# Chaos experiment: 01-pod-kill-graceful

Run: 2026-10-20 20:54 CEST on kind (3 nodes), 2 app replicas, PostgreSQL primary + replica.

## Hypothesis
Killing one of two replicas (graceful) under load causes at most 1% failed requests, all replicas are Ready again within 60 s, no stored call is lost, and no SLO alert fires.

## Method
4 workers sending POST /api/calls + GET for 60s through the NodePort (new connection per request). At t=15s: `kubectl delete pod call-router-6b945bd8db-lzq7x` (graceful). Afterwards every created call id is read back.

## Result
- Requests: `total=24796 ok=24796 errors=0 error_pct=0.00 err_window_s=0.0 first_err_ms=0 last_err_ms=0`
- Error codes: `` (000 = connection refused/reset/timeout)
- All replicas Ready again after: **6s**
- Alerts pending/firing right after the run: `none`
- Calls lost: **0** of 12398
- Pods after: call-router-6b945bd8db-6qcz7 on voice-platform-worker2 (restarts 0); call-router-6b945bd8db-n6dw9 on voice-platform-worker (restarts 0); 

## Verdict
PASS - hypothesis held.
