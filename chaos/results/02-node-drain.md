# Chaos experiment: 02-node-drain

Run: 2026-10-20 on kind (3 nodes: 1 tainted control plane + 2 workers), 2 app replicas,
PostgreSQL primary + 1 replica. Executed twice - once draining the node with the
PostgreSQL **replica**, once draining the node with the **primary** (now the default).

## Hypothesis
Draining a worker (planned maintenance) causes zero failed requests: pods are evicted gracefully one at a time (PodDisruptionBudget), the hard topology spread still lets the evicted app pod move to the remaining node (cordoned nodes are ignored), and CloudNativePG switches the primary away before evicting it.

## Method
4 workers of POST+GET (new connection per request, 2 s timeout) for 120 s through the NodePort.
At t=15 s: `kubectl drain <node> --ignore-daemonsets --delete-emptydir-data`, then `kubectl uncordon`
at the end and a rolling restart to spread the app pods again.

## Result

| | Run A - replica's node (`voice-platform-worker2`, 20:55 CEST) | Run B - primary's node (`voice-platform-worker2`, 21:03 CEST) |
|---|---|---|
| Requests | 40 354, **0 errors** | 14 836, **182 errors (1.23 %)**: 174 × connection refused/timeout, 8 × 503 |
| Error window | none | **71.6 s** (21:03:14 → 21:04:26 CEST) |
| Drain duration | 31 s | 45 s |
| App pods during drain | both on `voice-platform-worker` (spread allowed it, cordoned node ignored) | same |
| PostgreSQL primary | unchanged (`call-router-db-1`) | switchover `call-router-db-2` → `call-router-db-1` |
| Acknowledged calls lost | **0** | **0** |

Where the 71 s in run B went (PostgreSQL + operator logs, times CEST):

| Time | Event |
|---|---|
| 21:03:01 | drain starts, node cordoned |
| 21:03:13 | operator: *"Current primary is running on unschedulable node, switching over"* |
| 21:03:14 | old primary shuts down; app readiness (`SELECT 1`) starts failing → pods NotReady → connection refused at the NodePort |
| 21:03:14 → 21:03:46 | **32 s** - new primary waits for the old primary's Kubernetes **Lease** to expire (`Primary lease not yet acquired, retrying`) |
| 21:03:46 → 21:04:23 | **37 s** - promotion (`pg_promote`) - normally < 1 s, here slow because the single-VM box was CPU-starved (load average ≈ 6) |
| 21:04:23 | `server promoted`; app pods Ready again within ~3 s |

Side effects observed:
- The PostgreSQL instance on the drained node stays **Pending** until uncordon: its volume is node-local (`local-path`) and the other worker already hosts the other instance (required anti-affinity). The cluster ran on one instance meanwhile.
- Topology spread is enforced only at scheduling time: after uncordon both app pods stayed on one node until a rolling restart (`voice-platform-worker` + `voice-platform-worker2` afterwards).
- An earlier, interrupted attempt at ~21:00 CEST triggered a switchover at the exact time of the hourly `ScheduledBackup`; that backup **failed** (`rpc error ... exit status 1`) and `CallRouterBackupFailed` **fired** in Prometheus. Mitigated per runbook with `scripts/backup.sh` (21:10-21:13 CEST) → `LastBackupSucceeded=True`.
- The Prometheus pod was evicted by the drain as well (single replica, monitoring gap of ~1 min).

## Verdict
- Replica node: **PASS** - zero errors.
- Primary node: **FAIL against "zero errors"** - no data loss, but a 72 s write outage. A
  planned switchover is not free: the lease handover plus promotion is the downtime.

Follow-ups (tracked in the [postmortem](../../docs/postmortems/2026-10-20-database-outage.md)):
1. Before maintenance, do a manual switchover first (`kubectl cnpg promote`), then drain - the lease is *released* cleanly instead of expiring.
2. Tune `spec.primaryLease` only with care (shorter = faster handover, higher split-brain risk on a flaky network).
3. Run Prometheus with 2 replicas (or a PodDisruptionBudget) so maintenance doesn't blind monitoring.
4. Add a descheduler (or `rollout restart` in the maintenance runbook) to re-spread pods after uncordon.
