# Chaos experiment: 06-latency

Run: 2026-10-20 22:05 CEST on kind (3 nodes), 2 app replicas, 2 PostgreSQL instance(s).

## Hypothesis
A dependency adding 600 ms to every call (above the 500 ms SLO threshold) does not cause errors, but burns the latency error budget fast enough for CallRouterLatencyBudgetBurnFast to page within ~10 minutes.

## Method
`helm upgrade --set config.faultLatencyMs=600` (rolling update), then 4 workers of POST+GET for 8 minutes; finally back to 0.

## Result
- Requests: `total=6152 ok=6152 errors=0 error_pct=0.00 err_window_s=0.0 first_err_ms=0 last_err_ms=0`
- POST p99 latency (2m): **0.75 s** (600 ms injected + normal work); latency SLI (bad ratio, 5m): **0.50** (raw `0.49986`)
- CallRouterLatencyBudgetBurnFast firing after: **did not fire within 8 min**

## Why it did not fire (Prometheus queries right after the run, 22:05 CEST)
| Query | Value |
|---|---|
| 5-minute bad ratio, max | **50.5 %** - only `POST` is slowed; the `GET` half of the load stays fast |
| 1-hour bad ratio, max | **1.45 %** - far below the 14.4 % fast-burn threshold |
| API requests in the last 1 h | ~212 000 (mostly earlier chaos experiments at full speed) |
| API requests during the experiment (9 min) | ~5 900 (slow POSTs also slow the load generator down) |
| Latency alerts seen in the last 15 min | `CallRouterLatencyBudgetBurnSlow` **pending** (ticket); fast and medium: none |

The fast-burn alert needs the **1-hour AND the 5-minute** bad ratio above 14.4 %.
The 5-minute window crossed it within minutes, but the 1-hour window was diluted by
~36x more fast requests from the hour before. Also, back-of-the-envelope for steady
traffic (calculation, not measured): with half the requests slow, the 1-hour ratio
reaches 14.4 % after about 0.144 / 0.5 x 60 = **~17 minutes**, plus `for: 2m` - so the
"page within ~10 minutes" hypothesis was too optimistic even without the dilution.

## Verdict
**FAIL** - `CallRouterLatencyBudgetBurnFast` did not fire within 8 minutes.
- Held: injected latency caused **0 errors** (6152/6152 OK), so error-based alerts and
  the availability SLO correctly stayed quiet; the 5-minute latency SLI showed the
  problem immediately (50 %) and the slow-burn ticket alert went pending.
- Did not hold: no page within the window. This is the multi-window design working as
  intended (the 1-hour window makes the alert significant) but it means a "half of all
  requests are slow" incident pages after ~20 minutes, not 10.
- Follow-ups: re-run with `MINUTES=25` on a quiet cluster to measure the real
  time-to-page; consider a per-route latency SLO for `POST /api/calls` (the call
  set-up path users feel), so a slow POST is not averaged with fast GETs.
