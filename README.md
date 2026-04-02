# Beamwarden

An **Elixir-first clean-room port repository** for agent-harness and control-plane research.

This project rebuilds selected Claude-style harness concepts as a **daemon-first BEAM runtime** with:

- Mix/OTP-native session and workflow orchestration
- multi-node routing and daemon-aware CLI proxying
- lightweight runtime recovery metadata (`runtime.dets`)
- mirrored command/tool inventories for structural parity work
- an archived Python companion tree kept as a **reference subtree**, not a primary workspace

> **Primary workspace:** `elixir/`
>
> **Archived reference subtree:** `reference/python/`

---

## What this repository is

`Beamwarden` is not a verbatim source dump and not a drop-in replacement for Claude Code.
It is a **clean-room porting project** focused on:

- harness architecture
- tool and command inventory mirroring
- session/workflow lifecycle orchestration
- daemon-first runtime control
- recovery and multi-node control-plane behavior on the BEAM

The current repository is best understood as:

- **Elixir** = primary implementation workspace
- **Python** = archived structural mirror kept for comparison/reference

---

## What ships today

The Elixir workspace currently provides:

- a canonical `mix beamwarden` CLI surface
- daemon mode via `mix beamwarden daemon-run`
- supervised sessions and workflows
- tmux-free local orchestration runs with `run`, `run-status`, `task-list`, `worker-list`, `retry-task`, `cancel-run`, and `logs`
- daemon-aware session/workflow routing
- cluster ownership bookkeeping via `ledger.dets`
- lightweight runtime continuity via `runtime.dets`
- cross-host documentation for longname/cookie operation
- smoke/regression coverage for daemon, failover, and recovery paths

### Shipped runtime posture

The current Elixir runtime is:

- **daemon-first**
- **OTP-native**
- **multi-node aware**
- **best-effort distributed**, not consensus-backed

It is intentionally conservative and does **not** claim full Claude Code runtime equivalence.

---

## What does not ship yet

This repository does **not** currently provide:

- split-brain-safe consensus
- external durable coordination storage
- full payload replication across hosts
- complete upstream runtime parity
- production-grade cluster discovery beyond connected BEAM nodes

In short: this is a strong **research/runtime port**, not a finished clone of the original system.

---

## Repository layout

```text
.
├── elixir/                       # Primary Mix/OTP workspace
│   ├── lib/beamwarden
│   └── test
├── reference/
│   └── python/                   # Archived Python mirror subtree
├── docs/
│   ├── elixir-control-plane-overview.md
│   ├── elixir-cluster-daemon-review.md
│   └── elixir-daemon-operations.md
├── assets/
└── README.md
```

---

## Quick start

### 1. Verify the Elixir workspace

```bash
cd elixir
mix format --check-formatted
mix compile
mix test
```

### 2. Try the core CLI surface

```bash
cd elixir
mix beamwarden summary
mix beamwarden manifest
mix beamwarden setup-report
mix beamwarden bootstrap "review MCP tool"
mix beamwarden daemon-status
mix beamwarden control-plane-status
mix beamwarden cluster-status
mix beamwarden run "review this repo and propose fixes" --workers 2
mix beamwarden retry-task <run-id> <task-id>
mix beamwarden cancel-run <run-id>
mix beamwarden logs <run-id>
mix beamwarden start-session --id smoke-session "review MCP tool"
mix beamwarden session-status smoke-session
```

### 3. Start daemon mode

```bash
cd elixir
mix beamwarden daemon-run --name beamwarden_daemon
```

### 4. Use the daemon from another shell

```bash
cd elixir
BEAMWARDEN_DAEMON_NODE=beamwarden_daemon@$(hostname -s) \
BEAMWARDEN_DAEMON_COOKIE=clawcluster \
mix beamwarden daemon-status
```

---

## Cross-host daemon operation

For same-host smoke tests, shortnames are enough.

For cross-host operation, use:

- the same cookie on every participating node
- consistent shortname/longname mode across daemon and clients
- longnames when the daemon host uses an FQDN

Example:

```bash
# daemon host
cd elixir
BEAMWARDEN_DAEMON_COOKIE=clawcluster \
mix beamwarden daemon-run --name beamwarden_daemon --longname

# remote client
cd elixir
BEAMWARDEN_DAEMON_NODE=beamwarden_daemon@daemon.example.internal \
BEAMWARDEN_DAEMON_COOKIE=clawcluster \
BEAMWARDEN_DAEMON_NAME_MODE=longnames \
mix beamwarden daemon-status
```

See the full operator guide:

- `docs/elixir-daemon-operations.md`
- `docs/elixir-orchestrator-operations.md`

---

## Important docs

Start here if you want to understand the current system:

- `docs/elixir-control-plane-overview.md`
- `docs/elixir-cluster-daemon-review.md`
- `docs/elixir-daemon-operations.md`
- `docs/elixir-orchestrator-operations.md`

Planning/history docs:

- `docs/elixir-first-review.md`
- `docs/plans/2026-04-01-elixir-control-plane-design.md`
- `.omx/plans/`

---

## Elixir architecture map

Key runtime files:

- `elixir/lib/beamwarden/cli.ex` — CLI surface
- `elixir/lib/beamwarden/orchestrator.ex` — local run/task/worker orchestration facade
- `elixir/lib/beamwarden/run_server.ex` — per-run supervision and task aggregation
- `elixir/lib/beamwarden/external_worker.ex` — supervised external worker wrapper
- `elixir/lib/beamwarden/runtime.ex` — structural runtime mirror
- `elixir/lib/beamwarden/query_engine.ex` — turn/session engine
- `elixir/lib/beamwarden/control_plane.ex` — session/workflow orchestration facade
- `elixir/lib/beamwarden/daemon.ex` — daemon-mode bootstrapping and proxy logic
- `elixir/lib/beamwarden/daemon_supervisor.ex` — daemon-root supervision boundary
- `elixir/lib/beamwarden/daemon_node_monitor.ex` — node membership monitoring/reconciliation
- `elixir/lib/beamwarden/cluster_daemon.ex` — ledger/runtime bookkeeping
- `elixir/lib/beamwarden/session_server.ex` — supervised session worker
- `elixir/lib/beamwarden/workflow_server.ex` — supervised workflow worker

Mirrored inventory files:

- `elixir/priv/reference_data/commands_snapshot.json`
- `elixir/priv/reference_data/tools_snapshot.json`

---

## Archived reference subtree

### `reference/python/`

The Python subtree is the earlier clean-room mirror that established the original porting strategy.
It remains useful for:

- historical comparison
- manifest/parity/routing reference behavior
- smaller mirror-oriented verification

Verify it with:

```bash
cd reference/python
python3 -m unittest discover -s tests -v
```

The earlier in-tree Rust reference subtree has been removed. Historical docs may still mention it as archival context, but it is no longer part of the active repository.

---

## Verification status

The repo currently verifies through:

### Elixir

```bash
cd elixir
mix format --check-formatted
mix compile
mix test
```

### Python reference subtree

```bash
cd reference/python
python3 -m unittest discover -s tests -v
```

The Elixir suite now includes regression coverage for:

- daemon mode
- daemon fallback
- workflow/session proxying
- failover behavior
- recovery across repeated validation runs

---

## Current limitations

Important limits to keep in mind:

- quorum/failover is still **best-effort** across connected BEAM nodes
- payload durability is still weaker than ownership/routing durability
- cross-host operation is documented and partially exercised, but not validated as a real multi-machine production deployment here
- test-only cleanup can differ from long-running non-test runtime behavior

---

## Why Elixir is primary here

The project direction is to make Elixir the best home for:

- long-running control-plane behavior
- supervision and fault isolation
- resumable sessions/workflows
- daemonized multi-node orchestration
- operationally clear BEAM-native runtime semantics

This is the main reason the root README now centers the Elixir workspace instead of the archived Python port.

---

## Built with OmX

A large part of the restructuring, porting, verification, and review flow in this repository was orchestrated with **oh-my-codex (OmX)** on top of Codex.

Typical flows used here:

- `$team` for coordinated parallel work
- `$ralph` for persistence + verification loops

---

## Community

Join the [instructkr Discord](https://instruct.kr/) for discussion around:

- LLM tooling
- harness engineering
- agent systems
- Codex / OmX workflows

---

## Disclaimer

This repository is an independent clean-room engineering effort.
It is not affiliated with Anthropic.
