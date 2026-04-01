# Elixir Control-Plane Overview

`elixir/` is the primary workspace for this repository.

The port still follows the project's clean-room structural-mirror philosophy, but it now adds a **daemon-first OTP control plane** aligned with BEAM strengths: supervision, resumability, workflow orchestration, and long-running distributed service processes.

## What was added

- `ClawCode.SessionServer` — supervised, resumable session workers.
- `ClawCode.WorkflowServer` — supervised workflow/task state with persisted transitions.
- `ClawCode.ControlPlane` — the public API for session/workflow lifecycle calls.
- `ClawCode.ClusterDaemon` — DETS-backed ownership ledger for multi-node routing/failover.
- `ClawCode.DaemonSupervisor` — long-running root supervision boundary for cluster lifecycle services.
- `ClawCode.DaemonNodeMonitor` — nodeup/nodedown monitoring plus reconciliation nudges.
- `ClawCode.Daemon` — daemon-mode bootstrapping, status, stop, and CLI proxy support.

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
mix claw daemon-status
mix claw control-plane-status
mix claw cluster-status
mix claw start-session --id smoke-session "review MCP tool"
mix claw submit-session smoke-session "review MCP tool"
mix claw session-status smoke-session
mix claw start-workflow smoke-flow "Update README" "Update docs"
mix claw workflow-status smoke-flow
mix claw advance-task smoke-flow 1 completed "done"
```

## Verification

```bash
cd elixir
mix format --check-formatted
mix compile
mix test
```
