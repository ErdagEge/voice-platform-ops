# Chaos experiment: 03-node-failure

Run: 2026-10-20 21:49 CEST on kind (3 nodes), 2 app replicas, 2 PostgreSQL instance(s).

## Hypothesis
When the worker running one app replica AND the PostgreSQL primary dies, CloudNativePG promotes the replica and the surviving app replica keeps serving; requests fail only until the failure is detected (< 60 s), and no acknowledged call is lost.

## Method
4 workers of POST+GET for 180s. At t=15s: `docker stop voice-platform-worker2` (the kind node container), restarted after 120s.

## Result
- Requests: `total=19926 ok=19592 errors=334 error_pct=1.68 err_window_s=162.6 first_err_ms=1792525246375 last_err_ms=1792525408928` codes `000:326 503:8 `
- Errors from t+0s to t+162s after the node died
- Node marked NotReady after: **49s**; new DB primary after: **83s**
- Acknowledged calls lost: **0** of 9818

## After the node came back (observed by hand, times CEST)
- The node container was started again at t+120 s. The PostgreSQL instance on it
  (`call-router-db-2`) rejoined as a replica (3 restarts) and the cluster went back to
  *Cluster in healthy state* with `call-router-db-1` as primary.
- The **app pod on the restarted node did not recover on its own**: it went into
  `CrashLoopBackOff` (6 restarts). Its logs show `tcp connect (call-router-db-rw.voice:5432):
  non-existing domain - :nxdomain` - pods on that node could not resolve Service names
  right after the restart - so the boot-time migration timed out and the app exited.
- The `kube-proxy` pod on that node was recreated at ~21:51; after deleting the
  crash-looping app pod at 21:54 its replacement was Ready in < 25 s.

## Verdict
**FAIL** against the hypothesis "errors stop within 60 s".
- Held: no acknowledged call was lost (0 of 9818), CloudNativePG promoted the replica on
  its own, and the surviving app replica kept serving most traffic (1.68 % errors overall).
- Did not hold: errors spanned **162 s**, not < 60 s. Kubernetes needed **49 s** just to
  mark the node NotReady (until then the dead pod stayed in the Service endpoints, hence
  the `000` connection timeouts), and the new DB primary took **83 s** (node detection plus
  the primary lease expiring), during which writes failed (`503`).
- New finding: after an unplanned node restart, an app pod can stay broken (crash loop
  on DNS) until someone intervenes. Follow-ups: make the app keep retrying the DB at boot
  instead of exiting, and the "node restarted" step in the
  [CallRouterNoReadyPods runbook](../../docs/runbooks/CallRouterNoReadyPods.md).
