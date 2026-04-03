# Elixir Orchestrator Operations

This guide documents the **local Beamwarden orchestration surface** that sits beside the daemon/session/workflow APIs.

The goal of this slice is operational clarity, not tmux feature parity. Beamwarden should tell operators:

- which runs and tasks exist
- which workers are still active vs only persisted as last-known state
- whether a failed task was retried or a run was cancelled
- what recent event/output summaries were persisted for debugging

## Command surface

```bash
cd elixir
mix beamwarden run "review this repo" --workers 2
mix beamwarden run-status <run-id>
mix beamwarden task-list <run-id>
mix beamwarden worker-list
mix beamwarden retry-task <run-id> <task-id>
mix beamwarden cancel-run <run-id>
mix beamwarden logs <run-id>
mix beamwarden logs <run-id> --follow
mix beamwarden cleanup-state --older-than-seconds 86400
mix beamwarden cleanup-runs --ttl-seconds 86400
```

`logs` should always provide a persisted summary view.
`logs --follow` now replays the currently available event snapshot with stable `seq` cursors, emits `follow=history seq=<n>`, then attaches to the local log broker with `follow=live broker_node=<node> seq=<n>`. If the broker cannot be reached, Beamwarden degrades explicitly to persisted polling with `follow=degraded-persisted reason=<reason>`. It still avoids pretending that Beamwarden is tailing raw worker stdout/stderr directly.

## Worker reporting: active vs persisted

`worker-list` should distinguish between:

- **active workers** — workers currently registered in the runtime/supervision tree
- **persisted workers** — last-known snapshots loaded from disk after the worker has exited or the daemon has restarted

That distinction matters because a persisted row is **not** proof that the worker is still alive. It is only the last known Beamwarden snapshot.

Recommended operator reading:

- trust `health_state` first: `active` means the last heartbeat is still within the worker timeout, `stale` means the heartbeat window has expired
- use `heartbeat_at` + `heartbeat_timeout_at` to explain why a row is active or stale
- treat persisted-only rows as recovery/debugging evidence rather than liveness

## Task recovery reporting

`task-list <run-id>` stays task-focused, but it now adds a compact explanation layer:

- `assignment_state=unassigned|leased|lost_lease|requeued|terminal`
- `recovery_reason=worker_expired|node_down|daemon_restart|operator_retry|cancel_requested` when a reason is known
- `lease_expires_at=<iso8601>` when a lost lease is what explains the row
- `recovered_from_attempt` / `recovered_from_worker` for operator-triggered retries

Recommended operator reading:

- healthy queued tasks should read as `assignment_state=unassigned`
- healthy in-flight tasks should read as `assignment_state=leased` without extra recovery noise
- `assignment_state=lost_lease` means the task is still non-terminal but its previous lease is no longer trustworthy
- `recovery_reason=daemon_restart` means the persisted run snapshot survived but no live `RunServer` is registered
- `recovery_reason=node_down` means the assigned worker only exists as a persisted row
- `recovery_reason=worker_expired` means the assigned worker heartbeat window elapsed
- `recovery_reason=operator_retry` / `cancel_requested` distinguishes operator-driven transitions from automatic recovery evidence

## Lifecycle commands

### `retry-task <run-id> <task-id>`

Use this after a task has reached a terminal error state and should be re-queued.

Expected behavior:

- clear terminal error/result fields that would confuse the next attempt
- move the task back to `pending`
- keep task identity stable so follow-up status checks remain easy
- append a retry event so the retry is visible in logs/history

### `cancel-run <run-id>`

Use this when the operator wants the run to stop accepting or finishing more work.

Expected behavior:

- mark the run as `cancelling` immediately when work is still in flight
- stop assigning pending work
- move pending tasks to a cancelled terminal state immediately
- move in-progress tasks to `cancel_requested` until the worker reports back
- mark the run as `cancelled` once all in-flight tasks have acknowledged the stop
- append explicit cancellation lifecycle events (`run_cancel_requested`, `task_cancel_requested`, `task_cancelled`, `run_cancelled`)

This is a **best-effort local orchestration stop**, not a distributed consensus guarantee.

## Logs and persisted summaries

`logs <run-id>` should prefer a compact operator view over raw process replay.

The useful minimum is:

- recent orchestration events (`run_started`, `task_assigned`, `task_completed`, `task_failed`, `task_retried`, `run_cancelled`)
- follow-mode output should keep `seq=<n>` cursors stable across replay/live/degraded follow
- worker output summaries or final result/error text
- timestamps that let operators correlate the event stream with `run-status` and `worker-list`
- explicit metadata for `run_status`, `run_lifecycle`, and `event_source` so operators know whether they are reading a live runtime view or a persisted snapshot
- per-event `source=replay|live|degraded-persisted` labels so operators can tell which transport path produced a line

That gives Beamwarden an answer to "what happened?" even after the worker process is gone.

### Current `--follow` contract

The current command shape stays the same, but the runtime is now broker-backed:

- replay persisted history up to a stable cursor/sequence
- attach to a live broker on the current owner node when one is available
- label replayed lines as `source=replay`
- label broker-delivered lines as `source=live`
- emit an explicit live marker such as `follow=live broker_node=<node> seq=<n>`
- degrade explicitly to persisted polling with a marker such as `follow=degraded-persisted reason=<reason>` when broker attach fails
- label fallback polled lines as `source=degraded-persisted`
- preserve terminal markers such as `follow=complete status=<state> seq=<n>` and `follow=timeout status=<state> seq=<n>`

That gives operators a real live stream without changing the CLI contract or pretending every line is raw stdout/stderr.

## Cleanup commands

### Current behavior

Phase 3 keeps two operator-friendly cleanup entrypoints:

- `cleanup-state --older-than-seconds <n>` — retention-oriented cleanup keyed to older persisted artifacts
- `cleanup-runs --ttl-seconds <n>` — run/worker/event cleanup with the same retention intent but a run-focused command shape

Both commands are local-first and should never delete data for an active run.

### Phase 4 target cleanup semantics

Phase 4 should keep the command surface stable while changing the protection rules behind it:

- consult orchestration leases before deleting run, worker, or event artifacts
- skip anything that is `active`, `recovering`, or still within a recoverable lease window
- compact cold event history before deleting it outright
- report `skipped_active_runs`, `skipped_recovering_runs`, and `compacted_event_runs` in addition to deletion counts

That keeps cleanup predictable even after run ownership and recovery cross node boundaries.

## Phase 4 design checkpoints

Phase 4 is the broker/lifecycle/retention hardening slice. The current Phase 3 runtime already persists useful run, worker, and event snapshots, but the next implementation should preserve these review constraints:

- **separate liveness from history** — persisted rows are last-known state, not proof that a worker or run is still active
- **make cleanup lease-aware** — expiry must never delete data that still belongs to an active or recoverable run/worker lease
- **requeue with evidence** — when a lease expires or a worker is judged stale, append a visible recovery event before reassigning work
- **add true live follow semantics** — the live broker should deliver already-persisted events with resumable cursors instead of hand-wavy tailing claims
- **keep operator output compact** — recovery metadata should clarify why a task moved instead of turning `logs` into raw process replay
- **document bounded retention** — operators need to know which files are durable state vs recyclable cache/history

## Phase 4 extension design

Phase 4 should keep the same operator commands while making three concrete improvements:

1. **broker-backed live follow**
   - `logs <run-id> --follow` replays persisted history first
   - after replay, follow switches to the local broker path and only falls back to polling when attach fails
   - the rendered stream labels `source=replay`, `source=live`, and `source=degraded-persisted`
2. **multi-node lifecycle clarity**
   - `run-status`, `task-list`, and `worker-list` should distinguish `active`, `stale`, `expired`, `cancel_requested`, `cancelled`, `failed`, and `recovered`
   - recovery should append explicit events before a task is requeued or moved
3. **lease-aware cleanup**
   - `cleanup-state` / `cleanup-runs` should consult lease and ownership evidence before deleting persisted artifacts
   - cleanup output should explain why data was skipped (`active_lease`, `recovery_window`, `reachable_owner`), not only what was deleted

The important contract change is semantic, not syntactic: Beamwarden should become **more honest and more distributed** without forcing operators to learn a second CLI.

## Related design docs

For the concrete Phase 4 implementation-oriented design, see:

- `docs/beamwarden-orchestrator-phase4-review.md`
- `docs/plans/2026-04-02-beamwarden-orchestrator-phase4-plan.md`

## Review notes for this slice

The Phase 1 runtime already established a good shape for local runs (`RunServer`, `TaskScheduler`, `ExternalWorker`, persisted run/worker snapshots). Phase 4A should preserve that simplicity while making follow semantics more explicit:

- prefer explicit status/source fields over clever inference in CLI output
- keep retry/cancel semantics visible in persisted state
- persist small summaries first; avoid over-designing full log streaming before the operator surface is solid
- document every "last known state" view so operators do not confuse persisted snapshots with live liveness

## Verification commands

```bash
cd elixir
mix format --check-formatted
mix compile
mix test

cd ../reference/python
python3 -m unittest discover -s tests -v
```
