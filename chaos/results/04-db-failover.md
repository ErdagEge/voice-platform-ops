# Chaos experiment: 04-db-failover

Run: 2026-10-20 21:17 CEST on kind (3 nodes), 2 app replicas, PostgreSQL primary + replica.

## Hypothesis
If the PostgreSQL primary dies, CloudNativePG promotes the replica within 30 s; the app reconnects on its own (no pod restarts), errors are limited to that window, and no acknowledged call is lost.

## Method
4 workers of POST+GET for 90s. At t=15s: `kubectl delete pod call-router-db-1 --grace-period=0 --force` (primary).

## Result
- Requests: `total=26573 ok=26523 errors=50 error_pct=0.19 err_window_s=21.0 first_err_ms=1792523694242 last_err_ms=1792523715243` codes `000:42 503:8 `
- New primary `call-router-db-2` after **22s**; error window: **21s (t+2s .. t+23s)**
- App container restarts during the test: `0 0 ` (unchanged = 0 new)
- Acknowledged calls lost: **0** of 13263

## Verdict
PASS - failover within 22s, no data loss.
