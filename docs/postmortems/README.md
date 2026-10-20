# Postmortems

Blameless write-ups of incidents: what happened, the impact on our SLOs, why the
system allowed it, and what we change so it doesn't happen again. Process and
severities: [incident-response.md](../incident-response.md).

- Start from [TEMPLATE.md](TEMPLATE.md); name the file `YYYY-MM-DD-<slug>.md`.
- Required for every SEV1/SEV2 and for any incident that used > 10 % of an error budget.
- Times are always **Europe/Brussels** with the zone label (CET/CEST).
- Action items need an owner and a ticket; the review meeting checks last month's items.

| Date | Incident | Severity | Duration | Budget used | Found by |
|---|---|---|---|---|---|
| 2026-10-20 | [Database unavailable → API down](2026-10-20-database-outage.md) | SEV1 | 3 min 6 s | 1.4 % (availability) | chaos game day, experiment 05 |
