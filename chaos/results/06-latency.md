# Chaos experiment: 06-latency

Run: 2026-10-23 16:13 CEST on kind (3 nodes), 2 app replicas, 2 PostgreSQL instance(s).

## Hypothesis
A dependency adding 600 ms to every POST /api/calls (above the 500 ms SLO threshold) does not cause errors, but the latency fast-burn page (15m and 5m bad ratio above 14.4%) fires within this 25-minute run.

## Method
`helm upgrade --set config.faultLatencyMs=600` (rolling update), then 4 workers of POST+GET for 25 minutes; finally back to 0.

## Result
- Requests: `total=19176 ok=19176 errors=0 error_pct=0.00 err_window_s=0.0 first_err_ms=0 last_err_ms=0`
- POST p99 latency (2m): **0.7478688524590164s**
- Latency SLI bad ratio: 5m **0.49986297615785147**, 15m **0.49969073075903503**, 1h **0.2945511625149001**
- CallRouterLatencyBudgetBurnFast firing after: **551s**

## Verdict
PASS - latency is detected by the SLO alert, not by error counts.

## Background
Original run (2026-10-20 22:05 CEST, `MINUTES=8`) **FAIL**ed: 0 errors, POST p99 0.75 s, 5-minute latency bad ratio 50%, but `CallRouterLatencyBudgetBurnFast` never fired. The 1-hour bad ratio peaked at 1.45% because about 212 000 earlier fast requests diluted `rate()[1h]`. At a steady 50% bad ratio that 1h window needs about 17 minutes plus `for: 2m` to cross 14.4%, and the slower request rate during the injection (slow POSTs throttle the load generator) makes it worse. Re-running for 25 minutes on that busy cluster would still have missed.

Fix: the latency fast-burn long window is **15m** (still AND the 5m window, still 14.4x the 1% budget, still `for: 2m`). Fifteen minutes of bad latency is not diluted by the previous hour. Availability burn rates are unchanged. Promtool covers the diluted shape: fast traffic for an hour, then 50% slow at a lower rate; the 1h ratio stays under 14.4% and the page still fires, and it does not fire at the 8-minute mark.

Re-verify (kind up, Prometheus on localhost:9090): `bash chaos/06-latency.sh` (default `MINUTES=25`). The page should fire inside that window. `MINUTES=8 bash chaos/06-latency.sh` is the original failing duration.
