# Beamwarden Orchestrator Phase 4 Review

This note is the review/documentation companion for the **Phase 4 live broker + multi-node lifecycle** slice of the tmux-free Beamwarden orchestrator.

It starts from the Phase 3 baseline that existed before the Phase 4A broker landing:

- `Beamwarden.Orchestrator.follow_logs/3` replays persisted event history, emits `follow=streaming`, then polls `Beamwarden.EventStore`
- `Beamwarden.RunServer` owns local run/task lifecycle transitions and persisted snapshots through `Beamwarden.RunStore`
- `Beamwarden.ExternalWorker` / `Beamwarden.WorkerSupervisor` persist last-known worker state through `Beamwarden.WorkerStore`
- `Beamwarden.ClusterDaemon` already maintains a DETS-backed ownership ledger with `epoch`, `running`, `updated_at`, and `lease_expires_at` for session/workflow routing
- `Beamwarden.OrchestratorRetention` currently performs local-first time-based deletion for runs, workers, and event files

Phase 4 should **extend those primitives**, not replace them with a brand-new transport or control plane.

## Phase 4A shipped now

The current repo now lands the first Phase 4 slice:

- `Beamwarden.LogBroker` is the local-first boundary for append + subscribe delivery
- `Beamwarden.EventStore` persists monotonic per-run `seq` values and supports `list_since/2`
- `Beamwarden.Orchestrator.follow_logs/3` replays broker backlog with `source=replay`, emits `follow=history seq=<n>`, then attaches to live broker delivery with `follow=live broker_node=<node> seq=<n>`
- when broker attach is disabled/unavailable, follow mode degrades honestly with `follow=degraded-persisted reason=<reason>` and `source=degraded-persisted`

That means the operator contract is already more honest than Phase 3 while staying local-first and CLI-compatible.

## What is shipped now

The current runtime now establishes the operator contract that later Phase 4 work must preserve:

1. `mix beamwarden logs <run-id>` is a compact persisted summary view.
2. `mix beamwarden logs <run-id> --follow` is honest today: it replays persisted history, then either attaches to live broker delivery or degrades explicitly to persisted polling, without pretending to tail raw worker stdout/stderr.
3. `worker-list` separates active runtime workers from persisted last-known rows.
4. `run-status` can already mark persisted active-looking runs as `stale_runtime=true` when the `RunServer` is gone.
5. cleanup commands are bounded and operator-facing, but still **local-first** rather than cluster lease-aware.

That means Phase 4 is not a greenfield design. It is a hardening/extension phase for a runtime that already has useful CLI affordances.

## Phase 4B scope guard

The next worker-liveness slice is intentionally **worker-list only**. Until the broader lifecycle/lease phases land, it should:

- keep `run-status` focused on run lifecycle fields
- keep `task-list` focused on task assignment/result fields
- avoid expanding cleanup output into lease-aware skip-reason reporting
- avoid introducing raw worker stdout/stderr live tailing
- avoid adding a TUI/monitor surface

The regression guard for that boundary lives in `elixir/test/beamwarden_orchestrator_phase4b_scope_guard_test.exs`.

## Phase 4 review goals

Phase 4 should make Beamwarden materially stronger in three linked areas.

### 1. True live log broker semantics beyond persisted replay

Current gap after Phase 4A:

- broker-backed follow now exists, but worker payloads are still compact lifecycle/result summaries rather than richer progress frames
- the broker is still local-first; remote broker attach remains future work
- `ExternalWorker` still returns a single final summary/error rather than a richer progress stream

Required Phase 4 outcome:

- `logs --follow` keeps the same command shape and is now broker-backed
- the broker can replay persisted history **and** deliver live events without waiting for a file poll round-trip
- every emitted line clearly labels whether it came from `source=replay` or `source=live`
- live follow remains compact and operator-first; it must not degrade into an unreadable raw transport dump

Phase 4A implementation notes:

- `Beamwarden.LogBroker` currently runs as a local orchestration child and serializes append + fanout
- per-run `seq` cursors are persisted in the event envelopes themselves, not in a separate index service
- replay/live follow shares one cursor contract via `subscribe(run_id, after_seq)`
- `logs <run-id>` remains compact and summary-first; this slice intentionally does **not** add raw stdout/stderr tailing

### 2. Stronger multi-node lifecycle semantics

Current gap:

- orchestrator run/worker lifecycle is richer than before, but still local-first
- `ClusterDaemon` lease semantics exist for session/workflow ownership, not orchestrator runs/tasks/workers/events
- current run/task states do not distinguish all of:
  - active work
  - stale last-known runtime state
  - expired ownership/lease state
  - recovered/requeued work after peer loss

Required Phase 4 outcome:

- operators can tell the difference between **active**, **stale**, **expired**, **cancelled**, **failed**, and **recovered** work
- recovery decisions become event-backed and inspectable
- node loss or worker disappearance causes a visible lifecycle transition before reassignment

Concrete design direction:

- keep the current user-facing commands (`run-status`, `task-list`, `worker-list`, `logs`) and enrich their fields instead of inventing a separate control surface
- introduce explicit lease/recovery metadata for orchestrator entities:
  - run lease owner
  - task claim/attempt lease
  - worker lease + heartbeat freshness
  - recovery reason / recovered_from
- standardize lifecycle terms across CLI output and persisted state:
  - `active`
  - `stale`
  - `expired`
  - `cancel_requested`
  - `cancelled`
  - `failed`
  - `recovered`
- append recovery events before mutating task assignment state, for example:
  - `worker_stale`
  - `worker_expired`
  - `task_recovery_requested`
  - `task_recovered`
  - `run_recovered`
  - `node_unreachable`

### 3. Lease-aware cleanup and retention

Current gap:

- `Beamwarden.OrchestratorRetention.cleanup/1` only checks local `RunServer.running?/1` and `WorkerSupervisor.worker_pid/1`
- persisted files can look old even when related ownership/lease metadata is still active elsewhere in the cluster
- events, runs, and workers are deleted independently instead of by a lease-aware artifact policy

Required Phase 4 outcome:

- cleanup never deletes data for work that is still leased, still recoverable, or still needed for operator forensics
- retention is explicit per artifact class: runs, workers, events, and future live-log fragments
- cleanup reports why data was skipped, not only what was deleted

Concrete design direction:

- drive cleanup from run/worker lease state first, timestamp second
- consult cluster ownership/lease metadata before deleting persisted artifacts
- split retention classes:
  - active/recoverable state (never delete while leased)
  - completed forensic state (delete after retention TTL)
  - derived/transient broker fragments (delete more aggressively once summarized and unleased)
- make cleanup output include skip reasons such as:
  - `skip=active_lease`
  - `skip=recovery_window`
  - `skip=reachable_owner`

## Current code-review hotspots

Review these modules together when Phase 4 lands:

- `elixir/lib/beamwarden/orchestrator.ex`
  - current `logs/1`, `follow_logs/3`, stale-runtime rendering, and cleanup rendering
- `elixir/lib/beamwarden/run_server.ex`
  - run/task lifecycle transitions and recovery event ordering
- `elixir/lib/beamwarden/external_worker.ex`
  - progress emission, heartbeat freshness, and live output integration
- `elixir/lib/beamwarden/event_store.ex`
  - durable event format, event ids/cursors, and broker persistence contract
- `elixir/lib/beamwarden/orchestrator_retention.ex`
  - retention policy, skip reporting, and lease-aware deletion checks
- `elixir/lib/beamwarden/worker_supervisor.ex`
  - active vs persisted worker rendering and future remote worker visibility
- `elixir/lib/beamwarden/cluster_daemon.ex`
  - reusable lease/epoch semantics and cross-node ownership evidence
- `elixir/lib/beamwarden/daemon_node_monitor.ex`
  - nodeup/nodedown-triggered reconciliation and recovery nudges
- `elixir/lib/beamwarden/cli.ex`
  - preserve command shapes while adding richer operator-visible semantics

## Proposed operator invariants

Phase 4 should preserve these review invariants:

- **Persisted does not mean live.** Replayable history and last-known snapshots are evidence, not liveness proof.
- **Live follow must say when it is live.** Broker-backed follow should label replay vs live frames explicitly.
- **Recovery must leave breadcrumbs.** Expiry, failover, and requeue actions must append visible events before state mutation.
- **Cleanup must respect leases.** Time-based expiry alone is not enough in a multi-node runtime.
- **Compact CLI output still wins.** Richer semantics should appear as better labels and summaries, not a noisy raw transport dump by default.

## Proposed phased roadmap

### Phase 4A — broker-backed event model

- introduce `Beamwarden.LogBroker`
- append events through broker before `EventStore`
- add event ids / cursors / `source=replay|live`
- emit live progress events from `ExternalWorker`

### Phase 4B — orchestrator lease model

- persist run/task/worker lease metadata
- extend lifecycle output with stale/expired/recovered semantics
- reuse `ClusterDaemon` epoch/lease ideas for orchestrator ownership

### Phase 4C — recovery transitions

- detect stale/expired workers and node loss
- append explicit recovery events before requeue
- surface recovered attempts in `task-list`, `run-status`, and `logs`

### Phase 4D — retention hardening

- make cleanup lease-aware across runs/workers/events
- add skip reasons and retention classes to CLI output
- document operator expectations for retention windows and forensic availability

## Suggested review questions

Use these when reviewing the eventual Phase 4 implementation:

1. Does `logs --follow` clearly differentiate replayed persisted history from broker-delivered live events?
2. Can an operator tell whether a task is still active, merely stale, actually expired, or already recovered onto another worker/node?
3. Does every recovery/reassignment action append an explanatory event before task state changes?
4. Can cleanup skip leased or recoverable artifacts even when their timestamps are old?
5. Are the CLI changes additive and compatible with the current Beamwarden command surface?

## Documentation update rules

When syncing operator docs with Phase 4 code:

1. Describe the **current shipped contract** first, then the Phase 4 enhancement.
2. Keep `logs <run-id>` as the compact default and document any richer live-follow semantics as an extension of that contract.
3. Use the same lifecycle vocabulary everywhere: active/stale/expired/cancel_requested/cancelled/failed/recovered.
4. Document retention as a lease-aware policy, not only a TTL policy.
5. Keep README/operator-guide/plan language aligned so recovery and cleanup semantics do not drift.

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
