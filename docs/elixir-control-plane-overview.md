# Elixir Control-Plane Overview

`elixir/` is the primary workspace for this repository.

The port still follows the project's clean-room structural-mirror philosophy, but it now adds a **daemon-first OTP control plane** aligned with BEAM strengths: supervision, resumability, workflow orchestration, and long-running distributed service processes.

## What was added

- `Beamwarden.SessionServer` — supervised, resumable session workers.
- `Beamwarden.WorkflowServer` — supervised workflow/task state with persisted transitions.
- `Beamwarden.ControlPlane` — the public API for session/workflow lifecycle calls.
- `Beamwarden.ClusterDaemon` — DETS-backed ownership ledger for multi-node routing/failover.
- `Beamwarden.DaemonSupervisor` — long-running root supervision boundary for cluster lifecycle services.
- `Beamwarden.DaemonNodeMonitor` — nodeup/nodedown monitoring plus reconciliation nudges.
- `Beamwarden.Daemon` — daemon-mode bootstrapping, status, stop, and CLI proxy support.

## Current cluster/daemon posture

Shipped today:

- resumable OTP workers plus multi-node routing
- supervised daemon-first control-plane mode for connected BEAM nodes
- daemon-aware CLI proxying to a configured long-running node
- durable ownership metadata in the cluster ledger (`.port_sessions/cluster/<node>/ledger.dets`)

Not shipped yet:

- external consensus or split-brain-safe quorum
- payload durability beyond JSON snapshots
- production-grade cluster discovery beyond connected BEAM nodes

See `docs/elixir-cluster-daemon-review.md` for the current review note and limits.

## Representative CLI surface

```bash
cd elixir
mix beamwarden daemon-status
mix beamwarden daemon-run --name claw_code_daemon --longname
mix beamwarden control-plane-status
mix beamwarden cluster-status
mix beamwarden start-session --id smoke-session "review MCP tool"
mix beamwarden submit-session smoke-session "review MCP tool"
mix beamwarden session-status smoke-session
mix beamwarden start-workflow smoke-flow "Update README" "Update docs"
mix beamwarden workflow-status smoke-flow
mix beamwarden advance-task smoke-flow 1 completed "done"
```

`mix claw ...` remains available as a compatibility alias.

## Verification

```bash
cd elixir
mix format --check-formatted
mix compile
mix test
```


## Cross-host daemon operation

Use longname mode when the daemon node is addressed with a fully-qualified host name. The current implementation supports this without extra dependencies:

```bash
# daemon host
cd elixir
BEAMWARDEN_DAEMON_COOKIE=clawsecret mix beamwarden daemon-run --name claw_code_daemon --longname

# remote client
cd elixir
BEAMWARDEN_DAEMON_NODE=claw_code_daemon@daemon.example.internal \
BEAMWARDEN_DAEMON_COOKIE=clawsecret \
BEAMWARDEN_DAEMON_NAME_MODE=longnames \
mix beamwarden session-status smoke-session
```

Use the same cookie and the same name mode on every participating node. Shortnames remain the default for same-host/local development. `CLAW_*` env vars remain supported as compatibility fallbacks.
