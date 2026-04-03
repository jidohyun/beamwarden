# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [Unreleased]

### Added
- Added a local-first `Beamwarden.LogBroker` so `mix beamwarden logs <run-id> --follow` can attach to replayed history and then continue with live broker-delivered state events.
- Added focused Phase 4A regression coverage in `elixir/test/beamwarden_log_broker_test.exs` for monotonic event sequencing and replay-to-live handoff behavior.
- Added `docs/plans/2026-04-03-beamwarden-orchestrator-phase4a-verification-lane.md` to pin the verification contract for the broker-first slice.

### Changed
- Updated the orchestrator follow path to emit broker-aware replay/live/degraded semantics while preserving the existing CLI surface and local-first runtime model.
- Updated operator and review docs to describe the shipped Phase 4A broker-backed follow behavior more honestly.
- Extended persisted events to carry both `seq` and `event_seq` so older output/tests remain compatible during the broker transition.

### Fixed
- Prevented late control messages from crashing idle external workers during log-follow test harness execution.
- Kept Phase 4A follow verification green after integrating worker implementation, test, and documentation lanes.
