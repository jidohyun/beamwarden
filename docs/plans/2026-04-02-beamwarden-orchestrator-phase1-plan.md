# Beamwarden Orchestrator Phase 1 Implementation Plan

## Status
Proposed

## Depends on
- `docs/plans/2026-04-02-beamwarden-orchestrator-design.md`

## Phase 1 goal
Deliver the smallest useful **tmux-free orchestration runtime** inside Beamwarden.

Phase 1 should prove four things:

1. Beamwarden can start a **run** as a first-class runtime object.
2. Beamwarden can manage a small **task queue** for that run.
3. Beamwarden can spawn and supervise **local external workers** without tmux.
4. A user can observe the result entirely through the Beamwarden CLI.

This phase is intentionally local-only. No remote worker placement, no TUI, and no complex recovery semantics yet.

## User-facing target
By the end of Phase 1, this should work:

```bash
mix beamwarden run "review this repo and propose fixes" --workers 2
mix beamwarden run-status <run-id>
mix beamwarden task-list <run-id>
mix beamwarden worker-list
```

The user does **not** need tmux, OMX team mode, or pane inspection to complete the run.

## Scope

### In scope
- orchestration runtime bootstrapped under the Beamwarden supervision tree
- one `RunServer` per orchestration run
- local task queue and task assignment
- local-only external worker execution
- basic event and log capture in memory
- run/task/worker status reporting through CLI
- narrow regression coverage

### Out of scope
- multi-node worker scheduling
- DETS-backed orchestration recovery
- cancellation/retry
- `logs --follow`
- TUI / monitor mode
- provider-specific worker adapters beyond a minimal generic adapter

## Recommended implementation shape

### 1. New runtime modules
Add these modules first:

- `Beamwarden.OrchestratorSupervisor`
- `Beamwarden.RunServer`
- `Beamwarden.TaskScheduler`
- `Beamwarden.WorkerSupervisor`
- `Beamwarden.ExternalWorker`

Optional in Phase 1 if needed for boundary clarity:

- `Beamwarden.RunStore` (ETS-backed only in V1)
- `Beamwarden.WorkerRegistry`

### 2. Keep state hot-only in Phase 1
Use:

- `Registry` for run/worker lookup
- ETS for current orchestration state
- GenServer state for per-run coordination

Do **not** add DETS persistence in Phase 1 unless a boundary absolutely requires it.

This keeps the first slice narrow and lets us prove orchestration semantics before recovery semantics.

### 3. Worker execution model
Workers should be modeled as supervised wrappers around an external executable.

V1 implementation rule:

- worker receives one assigned task at a time
- worker emits final result only
- progress streaming can be coarse in Phase 1

The adapter can be intentionally simple:

- a shell command wrapper
- a Beamwarden-owned script adapter
- or a generic "echo/process" adapter used only to prove lifecycle

The point is to prove orchestration boundaries, not to solve every provider integration up front.

## CLI plan

### Add commands
Phase 1 should add:

- `mix beamwarden run <prompt> [--workers N]`
- `mix beamwarden run-status <run-id>`
- `mix beamwarden task-list <run-id>`
- `mix beamwarden worker-list`

### Command behavior

#### `run`
- creates a run id
- turns the prompt into an initial task set
- starts a `RunServer`
- starts up to `N` workers
- assigns tasks immediately
- returns a concise run summary

#### `run-status`
- shows:
  - run id
  - run status
  - task counts
  - worker counts
  - last update timestamp

#### `task-list`
- shows all tasks for the run with:
  - task id
  - status
  - assigned worker
  - result summary if completed

#### `worker-list`
- shows active orchestration workers with:
  - worker id
  - run id
  - state
  - current task id

## Internal data model

### Run state
Suggested run struct/map:

- `run_id`
- `prompt`
- `status`
- `created_at`
- `updated_at`
- `task_ids`
- `worker_ids`
- `completed_count`
- `failed_count`

### Task state
Suggested task struct/map:

- `task_id`
- `run_id`
- `title`
- `payload`
- `status`
- `assigned_worker`
- `result_summary`
- `error`
- `created_at`
- `updated_at`

### Worker state
Suggested worker struct/map:

- `worker_id`
- `run_id`
- `state`
- `current_task_id`
- `started_at`
- `heartbeat_at`
- `last_event_at`

## Concrete file plan

### New files
- `elixir/lib/beamwarden/orchestrator_supervisor.ex`
- `elixir/lib/beamwarden/run_server.ex`
- `elixir/lib/beamwarden/task_scheduler.ex`
- `elixir/lib/beamwarden/external_worker.ex`

Likely:
- `elixir/lib/beamwarden/run_store.ex`
- `elixir/lib/beamwarden/worker_store.ex`

### Files likely to change
- `elixir/lib/beamwarden/application.ex`
- `elixir/lib/beamwarden/cli.ex`
- `elixir/lib/beamwarden/control_plane.ex` (only if shared helpers are reused)
- `elixir/lib/beamwarden/models.ex` (if shared structs are appropriate)

### Test files to add
- `elixir/test/beamwarden_run_server_test.exs`
- `elixir/test/beamwarden_task_scheduler_test.exs`
- `elixir/test/beamwarden_external_worker_test.exs`
- `elixir/test/beamwarden_orchestrator_cli_test.exs`

## Execution order

### Step 1 — supervision scaffolding
- wire `Beamwarden.OrchestratorSupervisor` into `Beamwarden.Application`
- add registries/supervisors needed for runs and workers
- keep the tree isolated from the existing daemon/session/workflow path

Acceptance:
- app boots cleanly
- no existing tests break

### Step 2 — `RunServer`
- implement run creation and in-memory run state
- support task registration and completion aggregation

Acceptance:
- a run can exist with zero workers
- run status changes correctly once tasks complete/fail

### Step 3 — `TaskScheduler`
- implement pending/running/completed/failed transitions
- simple FIFO assignment only

Acceptance:
- tasks assign deterministically
- no task is assigned to multiple workers at once

### Step 4 — `ExternalWorker`
- implement external process spawn/wait/result capture
- return success/failure to the run

Acceptance:
- worker executes one assigned task
- terminal result is observable through the run

### Step 5 — CLI
- add `run`, `run-status`, `task-list`, `worker-list`
- keep output concise and stable enough for tests

Acceptance:
- a user can launch and inspect a run without tmux

## Test strategy

### Unit tests
- task state transitions
- run completion rules
- worker assignment rules
- external worker success/failure normalization

### Integration tests
- start a run with a fake external worker adapter
- verify tasks complete
- verify run status reflects the result
- verify worker list/task list commands show the expected runtime state

### Regression checks
Keep all existing verification green:

```bash
cd elixir
mix format --check-formatted
mix compile
mix test
```

Also keep the archived Python reference green:

```bash
cd reference/python
python3 -m unittest discover -s tests -v
```

## Risks and controls

### Risk 1 — External process management explodes scope
Control:
- use a minimal adapter in Phase 1
- no streaming complexity beyond what the CLI absolutely needs

### Risk 2 — Orchestrator overlaps too much with existing control plane
Control:
- keep orchestration as a separate supervision slice
- only share helpers where the boundary is already clean

### Risk 3 — CLI design drifts before runtime is stable
Control:
- lock Phase 1 CLI to four commands only
- defer monitor/follow/retry/cancel until later

## Acceptance criteria
Phase 1 is done when all of the following are true:

1. `mix beamwarden run ...` starts a run without tmux.
2. At least one local external worker can complete a task.
3. `run-status`, `task-list`, and `worker-list` report accurate state.
4. The new orchestration runtime coexists cleanly with the current daemon/control-plane runtime.
5. Existing Elixir and Python verification remain green.

## Recommended immediate next step
Start with **supervision scaffolding + `RunServer` only** in the first coding slice.

That keeps the first implementation diff small and gives us a stable root for:

- task scheduling
- worker supervision
- CLI exposure

without trying to solve the whole orchestration surface at once.
