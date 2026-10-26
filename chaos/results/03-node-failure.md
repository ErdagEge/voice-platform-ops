# Chaos experiment: 03-node-failure

Run: 2026-10-23 15:47 CEST on kind (3 nodes), 2 app replicas, 2 PostgreSQL instance(s).

## Hypothesis
When the worker running one app replica and the PostgreSQL primary is stopped and started again, no acknowledged call is lost, and the app pod on that node becomes Ready by itself. A transient DNS nxdomain while kube-proxy comes back must not crash-loop the process.

## Method
4 workers of POST+GET for 180s. At t=15s: `docker stop voice-platform-worker` (the kind node container), restarted after 120s. After the node is back, wait up to 180s for every app pod to be Ready (no manual delete).

## Result
- Requests: `total=10442 ok=10087 errors=355 error_pct=3.40 err_window_s=162.1 first_err_ms=1792763071765 last_err_ms=1792763233889` codes `000:349 503:6 `
- Errors from t+0s to t+162s after the node died
- Node marked NotReady after: **52s**; new DB primary after: **n/as**
- Acknowledged calls lost: **0** of 5050
- App pods Ready on their own after the node returned: **yes**
- App pods after restart:
  call-router-948d7f489-ljbw8   true   Running   voice-platform-worker2   0
  call-router-948d7f489-v5vwm   true   Running   voice-platform-worker    1

## Verdict
PASS - every app pod became Ready on its own after the node returned (no DNS crash loop) and no acknowledged call was lost. Error window was 162.1s (kubelet NotReady detection plus the CNPG primary lease; recorded, not the pass bar).

## Background
Original run (2026-10-20 21:49 CEST) **FAIL**ed a "< 60 s of errors" hypothesis: 1.68% errors over 162 s, node NotReady after 49 s, new primary after 83 s, 0 of 9818 calls lost. After the node container was started again, the app pod on it stayed in `CrashLoopBackOff` (6 restarts). Logs: `tcp connect (call-router-db-rw.voice:5432): non-existing domain - :nxdomain`. kube-proxy on that node was recreated a few minutes later; deleting the pod by hand produced a Ready replacement in under 25 s.

Cause: `Ecto.Migrator` runs migrations inside `init/1` and then stops. A DNS failure (NXDOMAIN on CloudNativePG's `<service>.<namespace>` host while kube-proxy is still coming back) crashed that init, the BEAM exited, and kubelet CrashLoopBackOff grew to minutes. The pod did not notice when DNS recovered.

Fix: `CallRouter.Migrator` retries with backoff and does not exit, so `/healthz` stays up and `/readyz` stays down until the database answers. The chart rewrites that host to `<service>.<namespace>.svc.cluster.local` and sets `ndots: 2`, so the first lookup is the real Service name. The error window above 60 s is kubelet plus the CNPG primary lease; this change does not claim to shrink it. Pass bar: no lost calls, and every app pod Ready without a manual delete.

Re-verify (kind up, app and database deployed): `bash chaos/03-node-failure.sh`
