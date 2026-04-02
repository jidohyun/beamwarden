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
mix beamwarden cleanup-runs [--ttl-seconds 3600]
```

`logs --follow` remains a **single-shot replay hint** in this slice: Beamwarden reports whether the log view is coming from a live runtime or only from persisted state, then replays the stored event summary once.

Today `logs --follow` is intentionally conservative: it replays the currently available event snapshot exactly once and then exits. When the run is still active, the CLI labels that output as a runtime snapshot replay; when the run is no longer active, it labels it as a persisted snapshot replay. In both cases Beamwarden avoids pretending it is tailing a live process stream.

Today `logs --follow` is intentionally conservative: it reuses the persisted event rendering and adds an explicit `follow=not_implemented_showing_persisted_events_only` banner instead of pretending Beamwarden is tailing a live process stream. That banner is part of the operator contract until real streaming lands.

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

- mark the run as cancelled
- stop assigning pending work
- move pending tasks to a cancelled terminal state
- mark in-progress tasks as cancelled once the runtime has acknowledged the stop
- append a run/task cancellation event for later inspection

This is a **best-effort local orchestration stop**, not a distributed consensus guarantee.

## Logs and persisted summaries

`logs <run-id>` should prefer a compact operator view over raw process replay.

The useful minimum is:

- recent orchestration events (`run_started`, `task_assigned`, `task_completed`, `task_failed`, `task_retried`, `run_cancelled`)
- worker output summaries or final result/error text
- timestamps that let operators correlate the event stream with `run-status` and `worker-list`
- explicit metadata for `run_status`, `run_lifecycle`, and `event_source` so operators know whether they are reading a live runtime view or a persisted snapshot

That gives Beamwarden an answer to "what happened?" even after the worker process is gone.

### Current `--follow` contract

Until Beamwarden grows a real log broker/follower, operators should read `logs <run-id> --follow` as:

- render the persisted event history first
- emit an explicit warning that live follow is not implemented
- avoid implying that the CLI is attached to a running worker stdout/stderr stream

That keeps the interface honest while preserving a stable command shape for the later streaming implementation.

## Phase 3 review checkpoints

Phase 3 is the recovery/lease hardening slice. The current Phase 2 runtime already persists useful run, worker, and event snapshots, but the next implementation should preserve these review constraints:

- **separate liveness from history** — persisted rows are last-known state, not proof that a worker or run is still active
- **make cleanup lease-aware** — expiry must never delete data that still belongs to an active run/worker process
- **requeue with evidence** — when a lease expires or a worker is judged stale, append a visible recovery event before reassigning work
- **keep operator output compact** — recovery metadata should clarify why a task moved instead of turning `logs` into raw process replay
- **document bounded retention** — operators need to know which files are durable state vs recyclable cache/history

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
