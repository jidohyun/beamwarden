# Beamwarden Orchestrator Phase 3 Review

This note is the review/documentation companion for the **Phase 3 recovery and lease hardening** slice of the tmux-free Beamwarden orchestrator.

It reflects the repository state after the Phase 2 lifecycle/logging work that shipped `retry-task`, `cancel-run`, persisted worker snapshots, and the compact `logs` operator view.

## What is shipped now

The current orchestrator already gives operators a useful local-first surface:

- persisted run snapshots via `Beamwarden.RunStore`
- persisted worker snapshots via `Beamwarden.WorkerStore`
- append-only event history via `Beamwarden.EventStore`
- explicit active-vs-persisted worker reporting through `worker-list`
- retry/cancel lifecycle events surfaced through `logs <run-id>`
- an honest `logs --follow` placeholder that keeps the command stable while live streaming is still unimplemented

That means Phase 3 is not starting from zero. It is hardening a runtime that already has operator-readable state and recovery clues.

## Phase 3 review goals

Phase 3 should make Beamwarden stronger in four linked areas:

1. **Lifecycle semantics**
   - active work needs clearer ownership/lease language
   - stale worker/task state must become distinguishable from merely persisted historical state
2. **Log retrieval semantics**
   - `logs` should stay compact and operator-first
   - if live follow is added later, it must remain explicit which lines came from persisted history vs live tailing
3. **Cleanup / expiry behavior**
   - persisted runs, workers, and event files need bounded-retention rules
   - cleanup must never silently erase state needed for in-flight recovery decisions
4. **Recovery behavior**
   - expired or abandoned work should be requeueable with a visible event trail
   - daemon restart behavior should preserve enough state to explain what Beamwarden recovered vs what it forgot

## Code-review hotspots

Review these modules together when Phase 3 lands:

- `elixir/lib/beamwarden/run_server.ex`
  - source of run-level lifecycle transitions and retry/cancel events
  - any recovery/requeue path should append explicit events before mutating task state
- `elixir/lib/beamwarden/orchestrator.ex`
  - keep operator rendering honest about persisted vs live information
  - avoid turning `render_logs/2` into raw transport replay
- `elixir/lib/beamwarden/cli.ex`
  - preserve clear user-facing semantics for `logs`, `worker-list`, and future cleanup/recovery commands
- `elixir/lib/beamwarden/run_store.ex`
- `elixir/lib/beamwarden/worker_store.ex`
- `elixir/lib/beamwarden/event_store.ex`
  - retention/expiry helpers should be explicit and testable
  - do not couple file cleanup to liveness inference without lease evidence
- `elixir/lib/beamwarden/external_worker.ex`
  - persisted heartbeat/last-event metadata should remain trustworthy inputs for expiry decisions

## Phase 3 invariants

The implementation should preserve these operator-facing invariants:

- **Persisted does not mean alive.** A JSON snapshot is only Beamwarden's last known view.
- **Recovery should leave breadcrumbs.** Requeue/expiry actions need log events, not silent mutation.
- **Cleanup must be bounded and predictable.** Operators need a documented retention rule for runs, workers, and events.
- **Follow must stay honest.** If Beamwarden is only showing persisted history, the CLI must say so.
- **Compact summaries win.** Phase 3 should improve recovery semantics without making the operator surface noisy.

## Suggested review questions

Use these questions when reviewing a Phase 3 implementation:

1. Can an operator tell the difference between a live worker, a stale worker snapshot, and an expired worker lease?
2. If a task is requeued after expiry, does `logs <run-id>` explain why?
3. Can cleanup delete the history of a run that is still active or still being recovered?
4. Does `logs --follow` clearly differentiate replay-only output from any future live tail mode, including the active-run vs persisted-run labels?
5. After a restart, does Beamwarden restore the minimum useful state without inventing liveness it cannot prove?

## Documentation update rules

When syncing operator docs with Phase 3 code:

1. Describe **current** behavior first, then any follow-on plan.
2. Label placeholders and best-effort behavior explicitly.
3. Keep retention/cleanup docs concrete: what is deleted, when, and why.
4. Reiterate that persisted snapshots are debugging/recovery evidence, not liveness proof.
5. Keep README/operator-guide language aligned so `logs`, `worker-list`, and recovery semantics do not drift.

## Verification contract

```bash
cd elixir
mix format --check-formatted
mix compile
mix test

cd ../reference/python
python3 -m unittest discover -s tests -v
```
