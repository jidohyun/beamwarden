# Beamwarden Orchestrator Phase 4 Design

## Status
Proposed

## Depends on
- `docs/plans/2026-04-02-beamwarden-orchestrator-design.md`
- `docs/elixir-orchestrator-operations.md`
- `docs/beamwarden-orchestrator-phase3-review.md`

## Goal
Phase 4 should harden the Beamwarden orchestrator from a **useful local-first runtime** into a runtime that can explain, recover, and clean up work honestly across daemon restarts and connected BEAM nodes.

This phase is specifically about three gaps that are still visible in the current implementation:

1. `logs --follow` only polls persisted events; it does not broker true live delivery.
2. run/worker/task liveness is still mostly inferred from local process presence plus last-known snapshots.
3. cleanup/retention is local-first and timestamp-based rather than lease-aware across nodes.

The Phase 4 target is still **operator-first and CLI-compatible**. The command surface stays stable:

```bash
mix beamwarden logs <run-id> --follow
mix beamwarden worker-list
mix beamwarden run-status <run-id>
mix beamwarden cleanup-state --older-than-seconds <n>
mix beamwarden cleanup-runs --ttl-seconds <n>
```

What changes is the truthfulness of the runtime behind those commands.

## Current runtime facts

Ground the design in what exists today:

- `Beamwarden.Orchestrator.follow_logs/3` replays `Beamwarden.EventStore.list/1`, emits `follow=streaming`, then polls for newly persisted events.
- `Beamwarden.EventStore` is append/list/delete only; events do not yet have broker cursors or subscriber semantics.
- `Beamwarden.ExternalWorker` persists `started_at`, `heartbeat_at`, and `last_event_at`, but it does not hold a lease or publish live log frames.
- `Beamwarden.OrchestratorRetention.cleanup/1` only protects runs via `Beamwarden.RunServer.running?/1` and workers via `Beamwarden.WorkerSupervisor.worker_pid/1`.
- `Beamwarden.ClusterDaemon` already maintains TTL-backed ownership records plus `runtime.dets`, but orchestration runs/workers do not yet participate in that ledger the way sessions/workflows do.

That means Beamwarden already has most primitives needed for Phase 4, but they are not yet connected into one consistent orchestration contract.

## Design principles

- **Persisted does not mean live.** Historical state and current liveness must stay separate.
- **Live delivery must still be resumable.** A broker frame without a persisted cursor is not enough.
- **Lifecycle should be explicit.** Operators should not infer stale/expired/recovered work from vague timestamps alone.
- **Cleanup must respect leases.** Nothing with an active or recoverable lease should be deleted.
- **Degrade honestly.** If Beamwarden falls back from broker delivery to persisted polling, the CLI should say so.

## Workstream 1 — true live log broker semantics

### Current problem
`logs --follow` is currently an honest persisted-event follower, but not a live broker:

- the CLI always reads from disk first
- follow mode discovers new lines only after they have already been persisted
- there is no cursor or subscription handshake
- worker stdout/stderr is not modeled as a live stream class

### Target contract
Keep the command the same, but change the semantics behind it:

1. replay persisted history up to a stable cursor
2. attach to the owning node's live log broker
3. receive broker frames as they are emitted
4. continue persisting every delivered frame so reconnect/resume stays deterministic
5. fall back to persisted polling only when the broker cannot be reached

### Proposed event envelope
Every emitted orchestration/log event should gain a stable envelope:

- `seq` — monotonically increasing per-run sequence
- `run_id`
- `kind` — `lifecycle`, `worker_stdout`, `worker_stderr`, `worker_summary`, `system`
- `task_id`
- `worker_id`
- `attempt`
- `node`
- `timestamp`
- `persisted_at`
- `payload`
- `source` — `history`, `broker`, or `degraded_poll`

The important rule is: **the broker publishes only events that already have a persisted `seq`**. That gives follow clients a resumable boundary.

### Proposed modules and boundaries

#### `Beamwarden.LogBroker`
Global broker process with per-run subscription tables.

Responsibilities:

- register subscribers for `run_id`
- fan out already-persisted envelopes to local subscribers
- expose subscription hooks for remote follow via `Cluster.rpc_call/5`
- emit explicit broker lifecycle markers (`broker_attached`, `broker_detached`, `broker_degraded`)

Implementation note:
Use OTP primitives already in the repo: `Registry`, monitored subscriber pids, and RPC to the owner node. No new dependency is required.

#### `Beamwarden.EventStore`
Extend the store so append returns an envelope with `seq` and metadata instead of only a raw map.

Needed additions:

- `append_envelope/2` or equivalent helper returning the persisted envelope
- `list_since(run_id, seq)` for cursor-based replay
- small index metadata per run (`last_seq`, maybe `last_compacted_seq` later)

#### `Beamwarden.ExternalWorker`
Workers should publish more than final summaries:

- worker stdout/stderr lines become `worker_stdout` / `worker_stderr` envelopes
- heartbeats can emit compact `worker_progress` or `worker_heartbeat` events without flooding the CLI
- final result/error remains summarized for compact `logs <run-id>` output

### CLI-visible behavior
`mix beamwarden logs <run-id> --follow` should preserve the existing command shape while surfacing which mode it is in.

Recommended markers:

- `follow=history seq=<n>` after persisted replay
- `follow=live broker_node=<node> seq=<n>` once attached to a broker
- `follow=degraded-persisted reason=<reason>` if Beamwarden must fall back to polling
- `follow=complete status=<state> seq=<n>` or `follow=timeout status=<state> seq=<n>`

That keeps the contract backwards-compatible but makes it clear when the operator is on a real live stream.

## Workstream 2 — stronger multi-node lifecycle semantics

### Current problem
The current orchestrator exposes:

- run `status`
- run `lifecycle`
- worker `presence`
- `stale_runtime=true` when a persisted running snapshot has no local `RunServer`

That is enough for local recovery clues, but not enough for multi-node semantics. In particular, Beamwarden still lacks explicit orchestration leases and consistent run/worker/task lifecycle terminology.

### Proposed model: keep status stable, add lifecycle/lease health
Do **not** break the current user-facing `status` values. Instead, layer explicit lifecycle fields underneath them.

#### Run fields
Keep `status` as:

- `pending`
- `running`
- `cancelling`
- `completed`
- `failed`
- `cancelled`

Add:

- `lifecycle_state` — `active | stale | expired | recovering | recovered | terminal`
- `lease_owner_node`
- `lease_epoch`
- `lease_expires_at`
- `recovery_state` — `none | queued | in_progress | completed | abandoned`
- `last_recovery_reason`

#### Worker fields
Keep worker `state` compact (`idle`, `busy`, later maybe `stopping`), but add:

- `presence` — `active | persisted`
- `health_state` — `active | suspect | stale | expired | stopped | recovered`
- `lease_owner_node`
- `lease_epoch`
- `lease_expires_at`
- `heartbeat_timeout_at`
- `recovered_from_worker_id` or `recovered_from_node`

#### Task fields
Keep task `status` values compatible (`pending`, `in_progress`, `cancel_requested`, `completed`, `failed`, `cancelled`), and add:

- `assignment_state` — `unassigned | leased | lost_lease | requeued | terminal`
- `lease_owner_worker_id`
- `lease_expires_at`
- `recovery_reason` — `worker_expired | node_down | daemon_restart | operator_retry | cancel`

### Proposed lease timing model
Use one lease model for runs and workers, with different deadlines:

- run lease renewed by the active `RunServer`
- worker lease renewed by the active `ExternalWorker`
- task assignment lease derived from the assigned worker lease

Suggested interpretation:

- **active** — latest heartbeat/renewal is within the healthy interval
- **suspect** — heartbeat missed once; keep work assigned but warn operators
- **stale** — lease is close to expiry; stop assigning new work to that owner
- **expired** — lease deadline passed; run recovery logic may reclaim work
- **recovered** — replacement owner has taken over and a recovery event was emitted

### How this maps onto current Beamwarden runtime
Reuse the current cluster ledger rather than inventing a second distributed registry.

#### `Beamwarden.ClusterDaemon`
Add orchestration scopes such as:

- `:run`
- `:run_worker`
- `:run_log_broker`

For each scope, persist:

- owner node
- epoch
- running flag
- lease expiry
- persisted path
- optional summary attrs (`run_status`, `worker_state`, `task_id`, `last_seq`)

#### `Beamwarden.RunServer`
Responsibilities added in Phase 4:

- renew the run lease on a timer
- persist lifecycle/lease metadata into the run snapshot
- emit recovery events when it reclaims or requeues stale work
- mark `lifecycle_state=recovering` before mutating tasks during recovery

#### `Beamwarden.ExternalWorker`
Responsibilities added in Phase 4:

- renew worker lease on a timer independent of final result delivery
- expose last delivered log `seq`
- emit explicit `worker_stale`, `worker_expired`, `worker_recovered` events when reconciliation decides so

### Required lifecycle events
Add operator-visible breadcrumbs for lease transitions:

- `run_lease_renewed`
- `run_marked_stale`
- `run_lease_expired`
- `run_recovery_started`
- `run_recovered`
- `worker_marked_stale`
- `worker_lease_expired`
- `task_requeued_after_expiry`
- `cleanup_skipped_active_lease`

Compact output still matters, so the default `logs` renderer should summarize these events rather than dumping raw internals.

## Workstream 3 — lease-aware cleanup and retention

### Current problem
`Beamwarden.OrchestratorRetention.cleanup/1` deletes:

- terminal runs older than a cutoff when no local `RunServer` exists
- workers with no local pid and old timestamps
- event files with no run snapshot and an old file mtime

That works for local tests, but it is not enough once ownership or recovery spans nodes.

### Target retention rules
Cleanup should become a **three-pass janitor**:

1. **scan** all run/worker/event artifacts plus cluster lease metadata
2. **protect** anything with an active or recoverable lease
3. **delete or compact** only artifacts whose lease and retention windows are both expired

### Proposed retention fields
Persist these directly into run/worker snapshots so the janitor can work from durable evidence:

- `retention_class` — `active | terminal_hot | terminal_cold | abandoned`
- `retention_until`
- `cleanup_eligible_at`
- `lease_expires_at`
- `last_seq`
- `event_log_path`

### Cleanup decision matrix

#### Run snapshot
Delete only when all are true:

- run `status` is terminal
- `lifecycle_state` is `terminal` or `expired`
- no active cluster lease remains for the run
- `retention_until` has passed

#### Worker snapshot
Delete only when all are true:

- worker `health_state` is `stopped`, `expired`, or `recovered`
- no task is still assigned to that worker lease
- the owning run is terminal or the worker has been superseded
- `retention_until` has passed

#### Event artifacts
Prefer compaction before deletion:

- keep the full event log while the run is active, stale, recovering, or recently terminal
- once the run becomes cold, compact to a summary window plus final lifecycle markers
- delete only after both the run snapshot and worker history are beyond retention

### Proposed janitor structure
Extend `Beamwarden.OrchestratorRetention` into explicit phases:

- `collect_candidates/1`
- `protect_live_leases/1`
- `compact_or_delete_events/1`
- `delete_terminal_runs/1`
- `delete_terminal_workers/1`

The CLI should still render one cleanup report, but that report should grow richer fields:

- `skipped_active_run_ids`
- `skipped_recovering_run_ids`
- `compacted_event_run_ids`
- `deleted_run_ids`
- `deleted_worker_ids`
- `deleted_event_run_ids`

## Proposed phased roadmap

### Phase 4A — broker-ready event envelopes
- add persisted `seq` metadata and `list_since/2`
- add `Beamwarden.LogBroker`
- wire `logs --follow` to broker attach/fallback semantics
- keep same CLI command shape

Acceptance:
- follow clients can attach live after replay
- reconnect can resume from a known `seq`
- fallback mode is explicit in CLI output

### Phase 4B — orchestration lease ledger
- register runs/workers/brokers in `Beamwarden.ClusterDaemon`
- renew leases from `RunServer` and `ExternalWorker`
- enrich snapshots with lifecycle/lease fields
- add stale/expired/recovered lifecycle events

Acceptance:
- operators can distinguish active vs stale vs expired vs recovered work
- node loss produces visible recovery events before task requeue
- `worker-list` and `run-status` show lease-aware state

### Phase 4C — lease-aware cleanup and retention
- refactor `Beamwarden.OrchestratorRetention` into scan/protect/delete phases
- protect recovering and leased artifacts
- compact cold event logs before deletion
- render richer cleanup reports

Acceptance:
- cleanup never deletes active or recoverable work
- cleanup reports explain what was skipped and why
- retained artifacts line up with documented retention classes

### Phase 4D — hardening and operator docs
- update README and operator guide wording to describe live/degraded follow semantics
- add failure-mode tests for broker fallback, lease expiry, and janitor safety
- document which artifacts are durable vs recyclable

Acceptance:
- docs and CLI output use the same lifecycle vocabulary
- regression tests cover recovery and cleanup edge cases

## Concrete file plan

### Files likely to change
- `elixir/lib/beamwarden/orchestrator.ex`
- `elixir/lib/beamwarden/run_server.ex`
- `elixir/lib/beamwarden/external_worker.ex`
- `elixir/lib/beamwarden/orchestrator_retention.ex`
- `elixir/lib/beamwarden/event_store.ex`
- `elixir/lib/beamwarden/worker_supervisor.ex`
- `elixir/lib/beamwarden/cli.ex`
- `elixir/lib/beamwarden/cluster_daemon.ex`

### Likely new files
- `elixir/lib/beamwarden/log_broker.ex`
- `elixir/lib/beamwarden/log_broker_supervisor.ex` or equivalent runtime wiring helper
- optional focused helpers for lifecycle classification / retention policy

### Tests to add or expand
- `elixir/test/beamwarden_orchestrator_phase4_test.exs`
- `elixir/test/beamwarden_orchestrator_cli_test.exs`
- `elixir/test/beamwarden_cluster_daemon_test.exs`
- `elixir/test/beamwarden_cluster_durability_test.exs`

## Review checklist

A Phase 4 implementation is ready for review when all of these are true:

1. `logs --follow` can honestly report whether it is replaying history, attached to live broker delivery, or degraded to persisted polling.
2. run/worker/task state distinguishes active, stale, expired, cancelled, failed, and recovered work without overloading one `status` field.
3. cleanup consults orchestration leases before deleting any run, worker, or event artifact.
4. every automatic recovery path emits a visible event before mutating task ownership.
5. the operator docs explain the retained artifacts and fallback behavior in the same terms the CLI prints.
