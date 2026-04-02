# Beamwarden Orchestrator Design (tmux-free)

## Status
Proposed

## Motivation
Beamwarden already has most of the ingredients for a durable control plane:

- a daemon-first runtime
- supervised session/workflow processes
- node-aware routing
- DETS-backed ownership and runtime metadata

Today, parallel operator workflows still depend on **tmux** through OMX team mode. That is good for fast iteration, but it means process orchestration, visibility, and failure handling still live outside the Beamwarden runtime.

The next Beamwarden-shaped step is to move from:

> "tmux panes coordinated by an external operator layer"

to:

> "Beamwarden itself supervising workers, tasks, logs, leases, and recovery"

The goal is **not** to reimplement a full product UI immediately. The goal is to make Beamwarden itself the orchestration runtime.

## Product framing
This design introduces a **tmux-free orchestration mode** where Beamwarden can:

- start a run
- spawn worker executors
- assign tasks
- stream progress
- persist run state
- recover after crashes
- distribute work across connected BEAM nodes

This should let a user do something like:

```bash
mix beamwarden run "review this repo and propose fixes" --workers 3
mix beamwarden run-status <run-id>
mix beamwarden task-list <run-id>
mix beamwarden logs <run-id> --follow
mix beamwarden retry-task <run-id> <task-id>
```

## Non-goals
This proposal does **not** try to:

- replace Codex/Claude/etc. with an in-VM LLM runtime
- solve consensus or split-brain-safe cluster coordination
- introduce Kubernetes-scale scheduling
- require a TUI before the runtime exists

The first version should stay local-first and BEAM-native.

## Recommended approach
Use Beamwarden as a **worker orchestration control plane** and treat each worker as an externally executed, supervised task runner.

That means:

- Beamwarden owns run/task state
- Beamwarden supervises worker lifecycle
- workers report progress and results back into Beamwarden
- tmux is not used for lifecycle, routing, or status

This is the best middle path because it preserves the current daemon/control-plane strengths while removing the pane-based dependency.

## Why this is better than tmux
tmux currently gives us five things:

1. process lifetime
2. a visible execution slot
3. crude state inspection
4. manual recovery
5. multi-worker convenience

Beamwarden can replace those with runtime-native primitives:

1. **Supervisor** instead of pane lifetime
2. **Worker registry + status** instead of visible panes
3. **Log/event store** instead of capture-pane
4. **lease/retry/requeue** instead of manual recovery
5. **node-aware scheduler** instead of same-window process splitting

## Runtime architecture

### 1. `Beamwarden.OrchestratorSupervisor`
Top-level supervision tree for orchestration mode.

Suggested children:

- `Beamwarden.RunRegistry`
- `Beamwarden.RunSupervisor`
- `Beamwarden.WorkerSupervisor`
- `Beamwarden.TaskScheduler`
- `Beamwarden.LogBroker`
- `Beamwarden.EventStore`
- `Beamwarden.LeaseManager`

This supervisor should sit next to the existing daemon/control-plane runtime, not replace it.

### 2. `Beamwarden.RunServer`
One `RunServer` per orchestration run.

Responsibilities:

- hold run metadata
- track task graph/state
- track assigned workers
- summarize run progress
- expose run-level status and completion state

Core run states:

- `pending`
- `running`
- `completed`
- `failed`
- `cancelled`

### 3. `Beamwarden.TaskScheduler`
Central task queue and assignment policy.

Responsibilities:

- track `pending/running/completed/failed`
- assign tasks to idle workers
- requeue expired/failed work
- enforce simple priority rules

V1 policy should stay intentionally simple:

- FIFO queue
- optional worker capability tags later
- no speculative scheduling in the first version

### 4. `Beamwarden.WorkerSupervisor`
Supervises worker executors.

Each worker is modeled as:

- `worker_id`
- `run_id`
- `node`
- `state`
- `claimed_task_id`
- `heartbeat_at`
- `capabilities`
- `last_event_at`

The key design choice is that **workers are not tmux panes**. They are Beamwarden-tracked execution units that may wrap an external CLI process.

### 5. `Beamwarden.ExternalWorker`
A GenServer responsible for one externally executed worker session.

Responsibilities:

- spawn the external process (`Port` or controlled OS process)
- stream stdout/stderr
- emit progress events
- report terminal success/failure
- handle cancellation and timeout

V1 should support **local external workers only**.
The external executable could be a generic adapter script first, then a Beamwarden-specific worker adapter later.

### 6. `Beamwarden.EventStore`
Append-only orchestration events.

Suggested event types:

- `run_started`
- `task_created`
- `worker_spawned`
- `task_assigned`
- `worker_heartbeat`
- `worker_progress`
- `task_completed`
- `task_failed`
- `task_retried`
- `run_completed`
- `run_cancelled`

Storage model:

- ETS for hot state
- DETS or append-only log for crash recovery

### 7. `Beamwarden.LogBroker`
Streams worker logs to:

- CLI views
- follow mode
- persisted summaries

This replaces "look at the pane" with:

```bash
mix beamwarden logs <run-id> --follow
mix beamwarden worker-status
```

## Control/data flow

### Leader path
1. User starts a run
2. `RunServer` creates tasks
3. `TaskScheduler` assigns tasks
4. `WorkerSupervisor` starts workers
5. `ExternalWorker` executes and emits events
6. `RunServer` aggregates results

### Worker path
1. worker starts and registers itself
2. claims assigned task
3. emits heartbeat and progress
4. writes final result or failure
5. becomes idle or terminates cleanly

## Multi-node design
This is where Beamwarden should eventually outperform a tmux-only approach.

### Node roles
- **daemon node**: orchestration authority
- **worker nodes**: execution capacity

### Scheduling model
- daemon chooses an eligible node
- remote worker is started under that node's `WorkerSupervisor`
- task claim includes lease metadata
- if a node dies, tasks are requeued after lease expiry

### Why this matters
tmux only gives same-machine concurrency.
Beamwarden orchestration should become a **BEAM-distributed worker system**.

## Recovery model

### Persisted state
Persist enough to recover:

- run metadata
- task states
- worker leases
- recent event log
- summarized worker outputs

### Crash recovery rules
- daemon restart: rebuild runs from persisted state
- worker crash: restart or requeue task
- node disappearance: expire lease and reschedule
- partial output: keep event/log tail for debugging

### Guardrails
- no consensus claims
- best-effort failover only
- explicit "last known state" reporting in CLI

## CLI surface
Recommended initial commands:

```bash
mix beamwarden run <prompt> [--workers N]
mix beamwarden run-status <run-id>
mix beamwarden task-list <run-id>
mix beamwarden retry-task <run-id> <task-id>
mix beamwarden cancel-run <run-id>
mix beamwarden worker-list
mix beamwarden worker-status [worker-id]
mix beamwarden logs <run-id> [--follow]
```

Later:

```bash
mix beamwarden monitor
```

for a TUI dashboard.

## Implementation phases

### Phase 1 — local orchestration runtime
- add `RunServer`
- add `TaskScheduler`
- add `WorkerSupervisor`
- add `ExternalWorker`
- support local-only workers
- expose `run`, `run-status`, `task-list`

### Phase 2 — observability and lifecycle
- add `LogBroker`
- add `EventStore`
- add `logs --follow`
- add cancel/retry support
- add explicit worker status views

### Phase 3 — recovery and leases
- persist run/task/lease state
- requeue expired tasks
- recover runs after daemon restart
- document failure semantics

### Phase 4 — multi-node execution
- spawn workers on connected nodes
- route tasks by node health/capability
- reassign work on node failure

### Phase 5 — operator UX
- add `monitor` TUI
- add event timeline views
- add richer queue and worker inspection

## Risks

### 1. External process supervision is harder than pane supervision
tmux hides many lifecycle details. Beamwarden will need to own:

- process startup
- I/O streaming
- cancellation
- timeout semantics
- stuck-process handling

### 2. Log streaming can become noisy
Without a clear log model, orchestration output will be harder to use than tmux.

### 3. Multi-node semantics can overcomplicate V1
We should not block the first release on distributed scheduling.

## Recommendation
Build this in **local-first phases**, but keep the abstractions cluster-ready from day one.

That means:

- make `RunServer` and `WorkerSupervisor` node-aware
- persist leases early
- keep scheduler logic decoupled from transport details
- avoid any new dependency unless OTP cannot cover the primitive cleanly

## One-sentence vision
Beamwarden should evolve from:

> "an Elixir control plane that sometimes coordinates tmux-driven workers"

into:

> "a BEAM-native orchestration runtime that supervises workers, routes tasks, persists state, and scales across connected nodes without needing tmux at all"
