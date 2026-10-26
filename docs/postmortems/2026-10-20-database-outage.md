# Postmortem: call-router API down for 3 minutes - database unavailable

| | |
|---|---|
| **Status** | Final |
| **Severity** | SEV1 (full API outage: calls failed for all customers; < 5 min, no data loss) |
| **Date** | 2026-10-20 |
| **Duration** | 3 min 6 s of failed calls (21:32:26 → 21:35:32 CEST) |
| **Customer impact** | 100 % of new calls failed (connection refused/timeout); no stored call lost |
| **Incident commander** | on-call engineer (game day) |
| **Author(s)** | ErdagEge |
| **Alert(s)** | [`CallRouterDatabaseDown`](../runbooks/CallRouterDatabaseDown.md) (page) |

> **This incident was reproduced on purpose** in a chaos game day on the local kind
> cluster ([experiment 05, fence](../../chaos/results/05-db-down-fence.md)): every
> PostgreSQL instance was stopped at once, like a crashed database or a lost storage
> backend. It is written up as if it were real, because the gaps it found are real.

## Summary
At 21:32:26 CEST all PostgreSQL instances of `call-router-db` stopped. Within 12 seconds
both call-router pods failed their readiness check (which runs `SELECT 1`), Kubernetes
removed them from the Service, and every incoming call was refused. `CallRouterDatabaseDown`
paged 94 s after the start. The database was started again at 21:35:27 and the API
recovered on its own 5-12 s later with no restarts and no data loss. The SLO-based alerts
**did not fire at all**, because the availability SLI never saw the failed calls.

## Impact
- **Calls:** every call attempted during 3 min 6 s failed. The load generator saw
  281 failures (266 connection refused/timeout, 15 × HTTP 503 in the first seconds).
  Acknowledged calls lost: **0** (all ~15 000 call ids acknowledged during the run were read back afterwards).
- **SLO / error budget (availability, 99.5 % / 30 days):**
  - *Real impact:* a full outage of 186 s = **1.4 % of the 30-day error budget**
    (budget = 0.5 % × 30 days = 3 h 36 min = 12 960 s). No budget-policy threshold
    ([incident-response.md](../incident-response.md#error-budget-policy)) is crossed.
  - *What the SLI measured:* only **23 bad requests** (the 503s the app itself returned)
    out of ~8 400 in the surrounding 4 minutes - a 5-minute error ratio peaking at
    **0.54 %**. By its own numbers the SLO was barely touched; the fast-burn page needs
    7.2 %. This gap is the main finding of this postmortem.
- **Latency SLO:** not affected (requests failed fast instead of slowly).

## Timeline
All times **Europe/Brussels (CEST, UTC+2)**. Sources: chaos log, Prometheus `ALERTS`, Alertmanager API, pod events.

| Time | Event |
|---|---|
| 21:32:26 | **Trigger:** all PostgreSQL instances stop (CNPG fencing `cnpg.io/fencedInstances=["*"]`). First failed call. |
| 21:32:26-38 | App returns 503 `storage` for calls that reach it; readiness `SELECT 1` fails (period 5 s × threshold 2). |
| 21:32:38 | Both app pods NotReady → Service has no endpoints → callers get connection refused/timeout. |
| 21:32:45 | `KubePodNotReady`, `KubeDeploymentReplicasMismatch` pending (15 min `for:` - would page much later). |
| 21:33:00 | `CallRouterDatabaseDown` pending (`call_router_db_up == 0` on both pods). |
| **21:34:00** | **`CallRouterDatabaseDown` firing** → Alertmanager → receiver `pager` (with `runbook_url`). **TTD 1 min 34 s.** |
| 21:34-21:35 | Runbook diagnosis: DB pods exist but PostgreSQL is stopped; `kubectl get cluster call-router-db -o jsonpath='{.metadata.annotations}'` shows `cnpg.io/fencedInstances`. *(Game day: the on-call response was simulated - the experiment lifts the fault after 3 minutes.)* |
| 21:35:27 | **Mitigation:** fencing removed, PostgreSQL starts. **TTM 3 min 1 s** (fixed by the game-day script; a real response would include acknowledge + diagnose time). |
| 21:35:30 | `CallRouterDatabaseDown` resolved. |
| 21:35:32 | Last failed call. |
| 21:35:39 | Both pods Ready, 0 restarts. **TTR 3 min 13 s.** Incident closed after the smoke test. |

## Root cause
The API depends on one PostgreSQL cluster for every request (both `POST` and `GET`
`/api/calls`). When all instances are unavailable there is no degraded mode, so the
service is down. That is accepted by design: a call that cannot be stored must not
be acknowledged.

The **contributing cause** is the observability gap. Five whys:
1. *Why did the SLO alerts stay silent?* The availability SLI is computed from
   `http_requests_total`, which only counts requests the app answered.
2. *Why did the app not answer?* Readiness depends on the database, so all pods were
   NotReady and the Service had no endpoints - requests failed in the network, before the app.
3. *Why was that not covered by another alert?* `CallRouterDown` checks `up`, and
   Prometheus keeps scraping NotReady pods (`up` stayed 1). Kubernetes' generic
   `KubePodNotReady` waits 15 minutes.
4. *Why did we still get paged?* Only because a cause-specific alert existed for this
   one cause (`CallRouterDatabaseDown`).
5. *Why is that a problem?* Any other reason for "all pods NotReady" (a bad readiness
   change, a broken Secret, a dependency we add later) would have caused an outage
   **with no page at all**.

## Trigger
All database instances stopped simultaneously (injected).

## Detection
Detected by `CallRouterDatabaseDown` after 94 s (1 min `for:` + up to 30 s evaluation
and the 5 s health interval). The page carried the runbook link. The symptom-based
SLO alerts did not fire (see root cause).

## Resolution and recovery
Per [the runbook](../runbooks/CallRouterDatabaseDown.md): check the DB pods →
running but PostgreSQL stopped → check the cluster annotations → fencing found → removed
(in the game day the removal was scripted). No app action was needed: the
Ecto pool reconnected, readiness turned green and the Service sent traffic again within
5-12 s. The liveness probe (`/healthz`, which does **not** check the DB) correctly kept
the pods alive, so there was no restart storm or crash loop.

## What went well
- Readiness failed fast (12 s) and cleanly: callers got a quick error, not a 30 s hang.
- Liveness is independent of the database → 0 restarts; recovery was automatic and fast.
- No acknowledged call was lost; storage errors are 503 and never "201 but not stored".
- The page arrived in < 2 min with a working runbook link.

## What went poorly
- The SLO-based alerting was blind to a full outage; the SLO report would show this
  incident as almost nothing.
- 15 503s were returned before readiness flipped; acceptable, but visible to callers.
- In a related experiment, a *planned* stop (hibernation) took 3 minutes longer than
  expected because PostgreSQL's smart shutdown waits for the app's pooled connections
  ([05-db-down-hibernate](../../chaos/results/05-db-down-hibernate.md)).

## Where we got lucky
- The cause matched the one dedicated DB alert we had. A different cause of "no Ready
  pod" would not have paged.
- The pods were already running. A pod **starting** while the DB is down crashes
  (migrations run at boot) and goes into CrashLoopBackOff, slowing recovery. This happened for real in
  [chaos experiment 03](../../chaos/results/03-node-failure.md): after a node restart the
  pod on it crash-looped on a DNS error until it was deleted by hand.

## Action items

| # | Action | Type | Priority | Owner | Status |
|---|---|---|---|---|---|
| 1 | Page on "no Ready pod" regardless of cause: `CallRouterNoReadyPods` (`kube_deployment_status_replicas_ready == 0` for 1 m) + promtool test + [runbook](../runbooks/CallRouterNoReadyPods.md) | detect | P1 | voice-platform | **Done** (2026-10-20), rule unit-tested with promtool |
| 2 | Measure availability where the caller is: load-balancer/Ingress metrics on GKE or a blackbox-exporter probe, and use that as the SLI | detect | P2 | voice-platform | Open |
| 3 | Don't crash at boot when the DB (or its DNS name) is unreachable: retry migrations in-process, stay unready, and qualify the CNPG host. A Helm pre-upgrade Job would not cover a pod starting after a node reboot (chaos 03) | mitigate | P2 | voice-platform | **Done** (2026-10-23): `CallRouter.Migrator` + `database.clusterDomain`, see [chaos 03](../../chaos/results/03-node-failure.md) |
| 4 | Planned DB maintenance: switch over first / lower `smartShutdownTimeout`; document in the DR runbook | process | P3 | voice-platform | Open |
| 5 | Re-run this game day after every change to probes, the DB chart or alert rules (chaos experiment 05) | process | P3 | voice-platform | Open |

## Supporting data
- Chaos report: [chaos/results/05-db-down-fence.md](../../chaos/results/05-db-down-fence.md)
- PromQL used:
  ```promql
  sum by (status) (increase(http_requests_total{job="call-router",route=~"/api/.*"}[4m]))   # @ 21:36 CEST
  max_over_time(slo:sli_error:ratio_rate5m{slo="call-router-availability"}[10m])           # 0.0054
  min_over_time(call_router_db_up[6m])                                                      # 0 on both pods
  ALERTS{alertname=~"CallRouter.*"}
  ```
- Runbooks: [CallRouterDatabaseDown](../runbooks/CallRouterDatabaseDown.md), [CallRouterNoReadyPods](../runbooks/CallRouterNoReadyPods.md)
