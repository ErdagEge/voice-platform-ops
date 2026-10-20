# Chaos experiment: 05-db-down-fence (database crash)

Run: 2026-10-20 21:39 CEST on kind (3 nodes), 2 app replicas, 2 PostgreSQL instance(s).

## Hypothesis
With the database completely down: readiness fails on all app pods within 15 s (traffic stops instead of erroring slowly), liveness does NOT restart them, CallRouterDatabaseDown pages within 2 minutes, and service recovers by itself within 60 s after the database is back, with no acknowledged call lost.

## Method
2 workers of POST+GET for 330s. At t=20s: `kubectl annotate cluster call-router-db 'cnpg.io/fencedInstances=["*"]'` (every PostgreSQL instance stopped at once, pods stay); after 180s the annotation is removed.

## Result
- Requests: `total=30129 ok=29848 errors=281 error_pct=0.93 err_window_s=186.3 first_err_ms=1792524746656 last_err_ms=1792524932984` codes `000:266 503:15 `
- All app pods NotReady after: **12s**
- CallRouterDatabaseDown pending after **40s**, firing after **101s**
- CallRouterAvailabilityBudgetBurnFast while down: **not active**
- App Ready again **12s** after the DB came back; container restarts: `0 0 ` -> `0 0 `
- Acknowledged calls lost: **0**

- Alertmanager: `CallRouterDatabaseDown` `severity=page` → receiver `pager`, with `runbook_url` .../docs/runbooks/CallRouterDatabaseDown.md
- Server-side metrics in the outage window (`increase(http_requests_total[4m])` at 21:36): only **23 × 503**; the other ~266 failed requests never reached the app (pods NotReady → no endpoints → connection refused / timeout at the Service).
- Availability SLI (5m bad ratio) peaked at **0.54 %** - far below the 7.2 % fast-burn threshold, so **no SLO alert fired**.

## Timeline (CEST)
| Time | Event |
|---|---|
| 21:32:26 | all PostgreSQL instances fenced (stopped) |
| 21:32:26 | first failed request |
| 21:32:38 | both app pods NotReady (readiness `SELECT 1` fails, `periodSeconds` 5 × `failureThreshold` 2) |
| 21:32:45 | `KubePodNotReady` / `KubeDeploymentReplicasMismatch` pending (15 min `for:`) |
| 21:33:00 | `CallRouterDatabaseDown` pending (`call_router_db_up` = 0 on both pods) |
| 21:34:00 | `CallRouterDatabaseDown` **firing** → page |
| 21:35:27 | fence removed (DB started) |
| 21:35:32 | last failed request |
| 21:35:39 | both app pods Ready, 0 restarts; 21:35:30 alert resolved |

## Verdict
**PASS with one important finding.**
- Held: readiness flipped in 12 s, liveness did not restart anything (no crash loop), the
  DB alert paged in 94 s (< 2 min), recovery took 12 s after the DB returned with no
  human action, and no acknowledged call was lost.
- Finding: the **availability SLO is blind to a full outage** of this kind. It is computed
  from requests the *app* answered; when every pod is NotReady, requests fail before they
  reach the app and are never counted. The only page came from the cause-based DB alert.
  A failure without a dedicated alert (e.g. all pods NotReady for another reason) would
  not have paged at all: `CallRouterDown` checks `up`, and Prometheus kept scraping the
  NotReady pods (`up` = 1 throughout); the generic `KubePodNotReady` waits 15 minutes.
  → analysed in [the postmortem](../../docs/postmortems/2026-10-20-database-outage.md).
