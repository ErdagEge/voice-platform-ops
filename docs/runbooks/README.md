# Runbooks

One page per alert, linked from each alert's `runbook_url` annotation. Every
page has the same structure: **what it means → impact → symptoms →
dashboards/queries → diagnosis → mitigation → escalation → verification**.

Golden rule: **mitigate first** (rollback, failover, scale), find the root cause after.
How incidents are run (severity, roles, comms): [incident-response.md](../incident-response.md).

| Alert | Severity | Source |
|---|---|---|
| [CallRouterAvailabilityBudgetBurnFast](CallRouterAvailabilityBudgetBurnFast.md) | page | SLO burn rate |
| [CallRouterAvailabilityBudgetBurnMedium](CallRouterAvailabilityBudgetBurnMedium.md) | page | SLO burn rate |
| [CallRouterAvailabilityBudgetBurnSlow](CallRouterAvailabilityBudgetBurnSlow.md) | ticket | SLO burn rate |
| [CallRouterLatencyBudgetBurnFast](CallRouterLatencyBudgetBurnFast.md) | page | SLO burn rate |
| [CallRouterLatencyBudgetBurnMedium](CallRouterLatencyBudgetBurnMedium.md) | page | SLO burn rate |
| [CallRouterLatencyBudgetBurnSlow](CallRouterLatencyBudgetBurnSlow.md) | ticket | SLO burn rate |
| [CallRouterDown](CallRouterDown.md) | page | symptom |
| [CallRouterPodRestarting](CallRouterPodRestarting.md) | ticket | symptom |
| [CallRouterDatabaseDown](CallRouterDatabaseDown.md) | page | data layer |
| [CallRouterDatabaseNoReplica](CallRouterDatabaseNoReplica.md) | ticket | data layer |
| [CallRouterWALArchivingFailing](CallRouterWALArchivingFailing.md) | page | data layer |
| [CallRouterBackupFailed](CallRouterBackupFailed.md) (also `CallRouterBackupTooOld`) | ticket | data layer |

Disaster recovery (restore from backup): [../dr.md](../dr.md).
