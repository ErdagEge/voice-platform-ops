# Chaos experiment: 05-db-down-hibernate (planned stop)

Run: 2026-10-20 21:28 CEST on kind (3 nodes), 2 app replicas, PostgreSQL primary + replica. Annotated at 21:19:05 CEST.

## Hypothesis
With the database completely down: readiness fails on all app pods within 15 s (traffic stops instead of erroring slowly), liveness does NOT restart them, CallRouterDatabaseDown pages within 2 minutes, and service recovers by itself within 60 s after the database is back, with no acknowledged call lost.

## Method
2 workers of POST+GET for 390s. At t=20s: `kubectl annotate cluster call-router-db cnpg.io/hibernation=on` (graceful stop: all PostgreSQL pods removed, volumes kept); after 240s `hibernation=off`.

## Result
- Requests: `total=63850 ok=63744 errors=106 error_pct=0.17 err_window_s=74.0 first_err_ms=1792524126403 last_err_ms=1792524200410` codes `000:94 503:12 `
- All app pods NotReady after: **193s**
- CallRouterDatabaseDown pending after **211s**, firing: **never** (the real outage was shorter than `for: 1m` + scrape delay)
- CallRouterAvailabilityBudgetBurnFast while down: **not active**
- App Ready again **19s** after the DB came back; container restarts: `0 0 ` -> `0 0 `
- Acknowledged calls lost: **0**

## What actually happened (times CEST)
| Time | Event |
|---|---|
| 21:19:05 | `hibernation=on`. CNPG asks the primary for a **smart shutdown**: PostgreSQL stops accepting *new* connections but waits for existing ones to close. The app's Ecto pool keeps 5 long-lived connections per pod, so nothing closes. |
| 21:19:05 → 21:22:05 | App keeps working over the already-open connections - no errors. |
| ~21:22:05 | `smartShutdownTimeout` (180 s default) expires → fast shutdown; the database is really down. |
| 21:22:06 | first failed request |
| 21:22:18 | both app pods NotReady (readiness `SELECT 1` fails) |
| 21:22:36 | `CallRouterDatabaseDown` pending |
| 21:23:07 | `hibernation=off` |
| 21:23:20 | last failed request; 21:23:26 both pods Ready again (19 s after wake-up), 0 restarts |

## Verdict
**Invalid as a "DB down" test, valuable as a finding.** The injected outage lasted
~60 s instead of 240 s because a graceful PostgreSQL stop waits up to 3 minutes for
clients that hold pooled connections. Consequences: a planned DB stop (hibernation,
maintenance) is **3 minutes slower than expected**, and the moment of the real outage
is not the moment of the command. The experiment was repeated with fencing
(immediate stop) → [05-db-down-fence.md](05-db-down-fence.md). Recovery itself held: no
restarts, no data loss, back 19 s after the database.
