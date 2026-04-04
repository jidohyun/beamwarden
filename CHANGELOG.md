# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [Unreleased]

### Added
- Added a local-first `Beamwarden.LogBroker` so `mix beamwarden logs <run-id> --follow` can attach to replayed history and then continue with live broker-delivered state events.
- Added focused Phase 4A regression coverage in `elixir/test/beamwarden_log_broker_test.exs` for monotonic event sequencing and replay-to-live handoff behavior.
- Added `docs/plans/2026-04-03-beamwarden-orchestrator-phase4a-verification-lane.md` to pin the verification contract for the broker-first slice.
- Added Phase 4B worker-liveness regression coverage, including `elixir/test/beamwarden_orchestrator_phase4b_scope_guard_test.exs`, to keep the worker-list-only scope explicit.
- Added Phase 4C regression coverage in `elixir/test/beamwarden_orchestrator_phase4c_task_recovery_test.exs` for task-list recovery reasons such as `worker_expired`, `node_down`, `operator_retry`, and `cancel_requested`.

### Changed
- Updated the orchestrator follow path to emit broker-aware replay/live/degraded semantics while preserving the existing CLI surface and local-first runtime model.
- Updated operator and review docs to describe the shipped Phase 4A broker-backed follow behavior more honestly.
- Extended persisted events to carry both `seq` and `event_seq` so older output/tests remain compatible during the broker transition.
- Updated `mix beamwarden worker-list` semantics to surface heartbeat-based worker health details so operators can distinguish active vs stale workers more clearly.
- Updated Phase 4 review/operator guidance to keep the next lifecycle slice constrained to worker-list-only changes.
- Updated `mix beamwarden task-list <run-id>` semantics to expose explicit assignment and recovery details so operators can tell why a task is healthy, lost its lease, or was retried.
- Added Phase 4C design/review documentation for task recovery semantics and task-list-only scope boundaries.

### Fixed
- Prevented late control messages from crashing idle external workers during log-follow test harness execution.
- Kept Phase 4A follow verification green after integrating worker implementation, test, and documentation lanes.
- Kept worker-liveness rollout scoped to `worker-list` without leaking Phase 4B changes into `run-status`, `task-list`, cleanup, raw tailing, or TUI work.
- Kept Phase 4C recovery semantics deterministic under verification so `task-list` reason names remain stable without broadening into `run-status`, `worker-list`, cleanup, raw tailing, or TUI work.
