# Chaos experiment: 01-pod-kill-sigkill

Run: 2026-10-20 20:51 CEST on kind (3 nodes), 2 app replicas, PostgreSQL primary + replica.

## Hypothesis
Killing one of two replicas (sigkill) under load causes at most 1% failed requests, all replicas are Ready again within 60 s, no stored call is lost, and no SLO alert fires.

## Method
4 workers sending POST /api/calls + GET for 60s through the NodePort (new connection per request). At t=15s: SIGKILL of the container on voice-platform-worker2 (`crictl stop --timeout 0`); kubelet restarts it in place. Afterwards every created call id is read back.

## Result
- Requests: `total=24350 ok=24224 errors=126 error_pct=0.52 err_window_s=0.6 first_err_ms=1792522176708 last_err_ms=1792522177265`
- Error codes: `000:126 ` (000 = connection refused/reset/timeout)
- All replicas Ready again after: **7s**
- Alerts pending/firing after the run (checked by hand at 20:53 CEST): `none`
- Calls lost: **0** of 12133
- Pods after: call-router-6b945bd8db-lzq7x on voice-platform-worker2 (restarts 1); call-router-6b945bd8db-n6dw9 on voice-platform-worker (restarts 0); 

## Verdict
PASS - hypothesis held.
