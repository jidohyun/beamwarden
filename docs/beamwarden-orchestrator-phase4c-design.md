# Beamwarden Orchestrator Phase 4C Design — Task Recovery Semantics

## Goal
Extend Phase 4's operator-truthfulness work from worker liveness into task recovery semantics. Phase 4C should make `task-list` explain **why** a task is stale, requeued, or recovered, not merely that its status changed.

## Why this slice now
- Phase 4A solved replay/live/degraded follow semantics.
- Phase 4B solved `worker-list` active/stale liveness clarity.
- The next operator blind spot is task causality: when work moves, stalls, or recovers, the CLI still makes humans infer the reason indirectly.

## User-visible target
Keep the command shape the same:

```bash
mix beamwarden task-list <run-id>
```

But enrich the output with explicit task recovery semantics such as:
- assignment state
- recovery reason
- lease owner worker id (when useful)
- lease expiry / timeout evidence (when useful)

## Proposed task model additions
Keep current task status values, but add a separate explanation layer:
- `assignment_state`: `unassigned | leased | lost_lease | requeued | terminal`
- `recovery_reason`: `worker_expired | node_down | daemon_restart | operator_retry | cancel_requested | none`
- `lease_owner_worker_id`
- `lease_expires_at`
- `recovered_from_attempt` or `recovered_from_worker_id` when applicable

## Rendering guidance
`task-list` should answer these questions quickly:
1. Is the task currently healthy or in recovery?
2. If in recovery, why?
3. Was the transition automatic or operator-driven?

Recommended rendering bias:
- show reason names plainly
- avoid timestamp-only inference
- keep healthy rows compact
- expose extra fields only when they clarify the transition

## Non-goals
- no `run-status` UI expansion in this slice
- no additional `worker-list` semantics work
- no cleanup/retention hardening
- no raw stdout/stderr tailing or TUI
- no full multi-node placement design

## Likely implementation touchpoints
- `elixir/lib/beamwarden/orchestrator.ex`
- `elixir/lib/beamwarden/run_server.ex`
- `elixir/lib/beamwarden/task_scheduler.ex`
- `elixir/lib/beamwarden/run_store.ex`
- `elixir/test/beamwarden_orchestrator_cli_test.exs`
- new Phase 4C task-list regression tests
- docs in `docs/elixir-orchestrator-operations.md` and Phase 4 review notes

## Acceptance summary
Phase 4C is successful when operators can read `task-list` and understand the reason behind stale/requeued/recovered tasks without opening tmux or inferring from worker logs.
