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
```

`logs` should always provide a persisted summary view.
`logs --follow` should stream newly persisted orchestration events until the run settles into a terminal state (or until an explicit follow timeout is hit).

## Worker reporting: active vs persisted

`worker-list` should distinguish between:

- **active workers** — workers currently registered in the runtime/supervision tree
- **persisted workers** — last-known snapshots loaded from disk after the worker has exited or the daemon has restarted

That distinction matters because a persisted row is **not** proof that the worker is still alive. It is only the last known Beamwarden snapshot.

Recommended operator reading:

- trust `state` + `current_task_id` for live runtime activity
- use `started_at`, `heartbeat_at`, and `last_event_at` to judge freshness
- treat persisted-only rows as recovery/debugging evidence rather than liveness

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
- follow-mode output should emit only new persisted event lines after the initial snapshot
- worker output summaries or final result/error text
- timestamps that let operators correlate the event stream with `run-status` and `worker-list`
- explicit metadata for `run_status`, `run_lifecycle`, and `event_source` so operators know whether they are reading a live runtime view or a persisted snapshot

That gives Beamwarden an answer to "what happened?" even after the worker process is gone.

## Persisted-state cleanup / expiry

Beamwarden keeps run snapshots, worker snapshots, and event logs under `.port_sessions/`.
Those files are intentionally durable enough for post-run debugging, but they should not accumulate forever.

Use:

```bash
mix beamwarden cleanup-state --older-than-seconds 86400
```

Expected behavior:

- delete only **persisted** run snapshots whose status is already terminal (`completed`, `failed`, `cancelled`)
- skip any run that still has a live `RunServer`
- delete persisted worker snapshots whose worker process is no longer registered
- delete event files for removed runs (and other orphaned old event logs)

This keeps cleanup conservative: Beamwarden prunes expired history, but it does not delete potentially recoverable in-flight runtime state.

## Review notes for this slice

The Phase 1 runtime already established a good shape for local runs (`RunServer`, `TaskScheduler`, `ExternalWorker`, persisted run/worker snapshots). Phase 2 should preserve that simplicity:

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
