# DR drill 2026-10-20 20:40 CEST

Scenario (`DISASTER=graceful`): the whole `voice` namespace is deleted (PostgreSQL primary + replica
and their volumes, app, Secrets, alert rules). Restore from the S3 backup store.

| Step | Time (CEST) |
|---|---|
| Base backup + WAL flush finished | 20:36:35 |
| Last write before the disaster | 20:37:50 |
| Disaster: `kubectl delete namespace voice` | 20:37:50 |
| Namespace fully gone | 20:39:39 |
| DB restored, app deployed, smoke test passed | 20:40:46 |

| Result | Value |
|---|---|
| Restored from backup folder | `call-router-db` → new cluster archives to `call-router-db-20261020T183939` |
| Set A (written before the backup) | **20 / 20** recovered |
| Set B (1/s for 75s after the backup) | **74 / 74** recovered |
| **RPO** (last write → newest recovered call) | **1s** |
| **RTO** (disaster → smoke test passing) | **176s** |
| Verdict | **PASS** |

RPO comes from WAL archiving (`archive_timeout: 60s`); calls after the last archived WAL
segment are lost. RTO includes deleting the namespace, a new PostgreSQL cluster
replaying the base backup and WAL, and a full `helm --atomic` deploy of the app.
