# Beamwarden Orchestrator Phase 4 Implementation Plan

## Status
In progress

> Update on 2026-04-03: the Phase 4A log-broker slice is now landed locally. `logs --follow` keeps the same CLI shape while replaying seq-backed history, attaching to `Beamwarden.LogBroker` for live delivery, and degrading explicitly to persisted polling when broker attach is unavailable.

## Depends on
- `docs/plans/2026-04-02-beamwarden-orchestrator-design.md`
- `docs/elixir-orchestrator-operations.md`

## Phase 4 goal
Make Beamwarden's orchestrator genuinely multi-node ready without breaking the current local CLI contract.

Phase 4 should prove three things together:

1. `logs --follow` can move from persisted-event replay to a true broker-backed backlog + live stream model.
2. runs, workers, and tasks have explicit distributed lifecycle semantics (`active`, `stale`, `expired`, `recovered`) backed by leases.
3. cleanup/retention decisions are driven by lease authority and terminal state instead of timestamps alone.

## Current baseline to preserve

The repository already ships a useful Phase 3 surface:

- `run-status` can show persisted stale runtime evidence
- `worker-list` can distinguish active workers from persisted-only rows
- `logs --follow` is intentionally conservative and replay-based
- `cleanup-state` skips active run/worker/event data

Phase 4 should build on that exact contract. Do not regress operator honesty just to simulate a more advanced distributed runtime.

## User-facing target

By the end of Phase 4, operators should still be able to use the current commands:

```bash
mix beamwarden run "review this repo" --workers 3
mix beamwarden run-status <run-id>
mix beamwarden task-list <run-id>
mix beamwarden worker-list
mix beamwarden logs <run-id> --follow
mix beamwarden cleanup-state --older-than-seconds 86400
```

But those commands should now expose stronger semantics:

- follow output differentiates replayed backlog from live broker events
- status output explains whether work is active, stale, expired, or recovered
- cleanup output explains whether artifacts were kept because of an active/stale lease

## In scope

- `Beamwarden.LogBroker` with replay/live subscription semantics
- monotonically ordered event cursors per run
- distributed worker/task lease metadata
- stronger worker/run/task liveness semantics
- lease-aware cleanup/retention rules
- docs and operator output updates
- focused regression coverage for the operator contract

## Out of scope

- consensus or split-brain-safe scheduling
- Kubernetes-style placement
- a TUI/monitor surface
- provider-specific remote worker adapters beyond one bounded executor path

## Recommended implementation shape

### 1. Add a real broker boundary

Introduce `Beamwarden.LogBroker` as a first-class runtime component.

Responsibilities:

- maintain per-run subscriber sets
- assign/forward `event_seq`
- serve replay + live streams from a cursor
- expose compact subscription metadata to CLI follow mode

Keep `Beamwarden.EventStore` as the durability boundary.
The broker is for delivery semantics, not historical storage.

#### Phase 4A broker-first delivery slice

To keep the implementation lane small, Phase 4A should stop at the broker-backed
`logs --follow` contract and leave lease/recovery work for later steps.

Broker-first boundaries:

- persist every orchestration event before it is published live
- assign a monotonic per-run `seq` / `event_seq` at the durability boundary
- let `Beamwarden.LogBroker` replay backlog from a cursor and then fan out live envelopes
- keep CLI follow semantics local-first; no raw stdout/stderr tail mode or monitor UI
- degrade explicitly to persisted polling when broker attach is unavailable

Minimal event envelope / cursor contract:

- required fields: `run_id`, `type`, `timestamp`, `persisted_at`, `seq`
- optional operator fields stay additive: `task_id`, `worker_id`, `attempt`, `summary`, `error`, `reason`
- replay API shape: `list_since(run_id, seq)` returns persisted envelopes with `seq > cursor`
- follow output should expose:
  - `follow=history seq=<n>`
  - `follow=live broker_node=<node> seq=<n>`
  - `follow=degraded-persisted reason=<reason> seq=<n>`
  - `follow=complete|timeout status=<state> seq=<n>`
- rendered event lines should label delivery origin as `source=replay`, `source=live`, or `source=degraded_poll`

Minimal file plan for this slice:

- `elixir/lib/beamwarden/event_store.ex` — assign/read stable `seq` metadata and `list_since/2`
- `elixir/lib/beamwarden/log_broker.ex` — per-run backlog + live subscription boundary
- `elixir/lib/beamwarden/run_server.ex` — publish persisted envelopes to the broker after append
- `elixir/lib/beamwarden/orchestrator.ex` — switch `logs --follow` to replay/live/degraded semantics
- `elixir/test/beamwarden_orchestrator_phase3_test.exs` — replay/live handoff regression
- `elixir/test/beamwarden_orchestrator_phase4_review_test.exs` — degraded follow fallback contract
- `docs/elixir-orchestrator-operations.md` / `README.md` — operator wording only

### 2. Model leases explicitly

Add explicit lease metadata to run/task/worker snapshots:

- `authority_node`
- `lease_owner`
- `lease_epoch`
- `lease_expires_at`
- `last_lease_renewed_at`
- `recovered_from_epoch`

This metadata should be persisted because recovery and cleanup both depend on it.

### 3. Separate terminal status from liveness

Do not overload `status`.

Keep:

- run/task status: `pending | running | completed | failed | cancelled`

Add:

- liveness: `active | stale | expired`
- recovery: `original | recovered | requeued`

This keeps CLI output readable and makes cleanup decisions testable.

### 4. Make cleanup retention lease-aware

Cleanup must answer two questions before deleting anything:

1. is this artifact still authoritative for an active or stale lease?
2. has the terminal/recovery retention window actually elapsed?

That implies different grace windows for:

- active work
- stale but not yet expired work
- expired but not yet recovered work
- recovered/superseded work
- fully terminal work

## Concrete file plan

### Likely modules to change
- `elixir/lib/beamwarden/orchestrator.ex`
- `elixir/lib/beamwarden/cli.ex`
- `elixir/lib/beamwarden/run_server.ex`
- `elixir/lib/beamwarden/task_scheduler.ex`
- `elixir/lib/beamwarden/external_worker.ex`
- `elixir/lib/beamwarden/orchestrator_retention.ex`
- `elixir/lib/beamwarden/event_store.ex`
- `elixir/lib/beamwarden/worker_store.ex`
- `elixir/lib/beamwarden/run_store.ex`

### New modules likely needed
- `elixir/lib/beamwarden/log_broker.ex`
- `elixir/lib/beamwarden/lease_manager.ex`

### Docs/tests to update
- `docs/elixir-orchestrator-operations.md`
- `docs/plans/2026-04-02-beamwarden-orchestrator-design.md`
- `elixir/test/beamwarden_orchestrator_phase3_test.exs`
- `elixir/test/beamwarden_orchestrator_phase4_review_test.exs`

## Execution roadmap

### Step 1 — broker semantics without remote placement
- add `LogBroker`
- emit cursor metadata (`event_seq`, `source`)
- update `logs --follow` to consume backlog + live events from one cursor contract

Acceptance:
- follow mode still works for local runs
- output distinguishes replay vs live delivery
- no duplicate event lines when switching from backlog to live streaming

### Step 2 — lease metadata and lifecycle states
- add explicit lease fields to run/task/worker snapshots
- add `active/stale/expired/recovered` semantics
- surface those fields in `run-status` and `worker-list`

Acceptance:
- operators can tell if persisted data is active, stale, or recovered
- stale runtime does not masquerade as live liveness

### Step 3 — multi-node scheduling handshake
- choose authority node for worker placement
- assign tasks with lease ownership metadata
- allow replacement/requeue after expiry

Acceptance:
- node disappearance can be described as stale -> expired -> requeued/recovered
- duplicate ownership is prevented within Beamwarden's best-effort lease model

### Step 4 — lease-aware cleanup and retention
- teach cleanup to consult lease/recovery metadata
- keep compact summaries after warm artifacts are deleted
- expose skipped reasons in cleanup output

Acceptance:
- active and stale leases are never deleted
- recovered and terminal artifacts age out predictably
- orphaned event files can be purged without harming live recovery

## Test strategy

### Regression tests
- current `logs --follow` contract stays explicit about persisted replay
- persisted non-terminal snapshots are marked as stale runtime evidence
- cleanup skips active run/worker/event artifacts even with aggressive retention settings

### Phase 4 integration tests to add next
- broker replay/live cursor handoff without duplicates
- lease expiry requeues work with visible recovery events
- recovered workers/runs retain prior epoch evidence but only one authority lease
- cleanup keeps stale leases but purges superseded epochs after retention

## Review guardrails

- prefer new metadata fields over renaming stable CLI fields
- keep logs operator-first; do not regress to raw noisy transport dumps
- every recovery or cleanup action should leave an event breadcrumb
- do not couple retention deletion to timestamps alone once leases exist

## Verification contract

```bash
git diff --check
cd elixir
mix format --check-formatted
mix compile
mix test

cd ../reference/python
python3 -m unittest discover -s tests -v
```
