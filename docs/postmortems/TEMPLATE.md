# Postmortem: <short title>

> **Blameless.** We describe what the *system* allowed to happen, not who made a
> mistake. People acted sensibly with the information they had; if a person could
> break production with one command, that is a missing guard rail, not a bad engineer.
> Copy this file to `YYYY-MM-DD-<slug>.md` within 2 working days of a SEV1/SEV2.

| | |
|---|---|
| **Status** | Draft / In review / Final |
| **Severity** | SEV1 / SEV2 / SEV3 (see [incident-response.md](../incident-response.md#severity-levels)) |
| **Date** | YYYY-MM-DD |
| **Duration** | detection → resolution, e.g. 6 min |
| **Customer impact** | who noticed what, e.g. "100% of new calls rejected for 4 min" |
| **Incident commander** | role/name |
| **Author(s)** | |
| **Alert(s)** | e.g. `CallRouterDatabaseDown` + link to the runbook |

## Summary
Two or three sentences a manager can read: what broke, the impact, how it was fixed.

## Impact
- Users/calls affected (numbers, not adjectives).
- **SLO / error-budget impact**: bad events ÷ allowed bad events in the 30-day
  window, per SLO (availability, latency). State whether the
  [error budget policy](../incident-response.md#error-budget-policy) is triggered.

## Timeline
All times **Europe/Brussels (CET/CEST)** — always write the zone label.

| Time | Event |
|---|---|
| HH:MM:SS | First symptom (trigger) |
| HH:MM:SS | Alert pending / firing |
| HH:MM:SS | Acknowledged, incident declared |
| HH:MM:SS | Mitigation applied |
| HH:MM:SS | Recovered (SLIs back to normal) |
| HH:MM:SS | Incident closed |

Key durations: **time to detect (TTD)**, **time to mitigate (TTM)**, **time to recover (TTR)**.

## Root cause
What happened technically and *why the system allowed it*. Use "5 whys"
until you reach something we can change (a design, a missing alert, a process).

## Trigger
The specific event that exposed the root cause (a deploy, a node failure, ...).

## Detection
How we found out. Did the right alert fire? Was it fast enough? Did any alert
stay silent that should have fired?

## Resolution and recovery
What was done, in order, and what made recovery fast or slow.

## What went well
-

## What went poorly
-

## Where we got lucky
-

## Action items
Each one has an owner, a priority and a tracking ticket. Prefer items that
*prevent* or *detect* over "be more careful".

| # | Action | Type (prevent / detect / mitigate / process) | Priority | Owner | Ticket |
|---|---|---|---|---|---|
| 1 | | | P1 | | |

## Supporting data
Grafana links / screenshots, PromQL used, log queries, related runbooks.
