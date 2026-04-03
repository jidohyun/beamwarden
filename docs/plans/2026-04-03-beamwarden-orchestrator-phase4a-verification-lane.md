# Beamwarden Orchestrator Phase 4A Verification Lane

## Status
In progress

## Purpose
Lock the Phase 4A broker contract behind a small, explicit verification lane so implementation can land without drifting the operator surface.

This lane is intentionally limited to:
- event cursor sequencing (`event_seq`)
- broker-backed `logs --follow` replay/live semantics
- compact operator-facing markers

It does **not** expand into raw stdout/stderr tailing, TUI work, or broader Phase 4B/4C lease recovery semantics.

## Current worker-2 test assets

### Existing regression kept green
- `elixir/test/beamwarden_orchestrator_phase3_test.exs`
  - follow harness fixed to release the real worker process instead of the test process
  - current persisted-polling contract remains covered

### New red/green acceptance target
- `elixir/test/beamwarden_log_broker_test.exs`
  - `event store assigns monotonic event_seq values per run`
  - `logs --follow hands off from replay to live delivery without duplicate cursors`

## Phase 4A contract this lane expects

### 1. Event cursor sequencing
Every orchestration event persisted for a run should carry a monotonically increasing `event_seq`.

Minimum expectations:
- first event in a run gets `event_seq=1`
- later events increase by exactly one within the same run
- `EventStore.list/1` returns events with those cursors preserved

### 2. Replay -> live handoff
`mix beamwarden logs <run-id> --follow` should:
- replay already-persisted events first
- label replayed entries with `source=replay`
- switch to broker delivery with an explicit `follow=live` marker
- label broker-delivered entries with `source=live`
- finish with a terminal marker containing the run status

### 3. No duplicate operator-visible events
The handoff from backlog replay to live subscription must not emit the same `event_seq` twice.

Operator-visible proof:
- extracted `event_seq` values stay sorted
- extracted `event_seq` values stay unique

## Expected implementation touchpoints
The implementation lane should satisfy this verification lane by updating the existing local-first runtime around:
- `elixir/lib/beamwarden/event_store.ex`
- `elixir/lib/beamwarden/orchestrator.ex`
- `elixir/lib/beamwarden/run_server.ex`
- `elixir/lib/beamwarden/orchestrator_supervisor.ex`
- new broker boundary: `elixir/lib/beamwarden/log_broker.ex`

## Verification sequence

### Green now
These should already pass in the verification lane:
```bash
git diff --check
cd elixir && mix format --check-formatted
cd elixir && mix compile
cd elixir && mix test test/beamwarden_orchestrator_phase3_test.exs
```

### Expected red until Phase 4A implementation lands
```bash
cd elixir && mix test test/beamwarden_log_broker_test.exs
```

Current expected failure reasons:
- no `event_seq` on persisted events yet
- follow output still uses the Phase 3 polling contract (`follow=streaming`) instead of replay/live broker markers

### Full repo verification after implementation merge
```bash
git diff --check
cd elixir && mix format --check-formatted
cd elixir && mix compile
cd elixir && mix test
cd ../reference/python && python3 -m unittest discover -s tests -v
```

## Merge / handoff note
Implementation can be considered Phase 4A-ready when:
1. the new broker test file turns green without weakening its assertions
2. the Phase 3 follow regression remains green
3. operator output still stays compact and local-first

## Known blocker
Worker-2 does not have the broker/event-seq implementation in this worktree yet, so this lane currently defines the acceptance target and the exact red tests the implementation must satisfy.
