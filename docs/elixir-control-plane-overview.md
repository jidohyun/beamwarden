# Elixir Control-Plane Overview

`elixir/` is now the primary workspace for this repository.

The Elixir port still follows the project's clean-room structural-mirror philosophy, but it now adds an OTP-native control plane that is better aligned with what Elixir is good at: supervision, resumability, and workflow/task coordination.

It also owns the mirrored snapshot/reference data it executes against under `elixir/priv/reference_data`, so the Python and Rust trees are reference-only companions rather than active dependencies of the Mix workspace.

## What was added

- `ClawCode.SessionServer` — supervised, resumable session processes backed by the existing query engine and session store.
- `ClawCode.WorkflowServer` — supervised workflow/task state with persisted task transitions.
- `ClawCode.ControlPlane` — public facade for starting, resuming, inspecting, and advancing sessions/workflows.
- `ClawCode.Application` — registries + dynamic supervisors for sessions and workflows.
- Companion mirror helpers for the remaining lightweight Python concepts (`query`, `task`, cost hooks, dialogs, onboarding, REPL banner, and tool definitions).

## Current cluster/daemon posture

The control plane already supports distributed routing across connected BEAM nodes, but it should still be described as:

- **shipped today:** resumable OTP workers plus multi-node routing
- **not shipped yet:** quorum-backed ownership, daemon-first cluster continuity, and a dedicated cluster-coordinator supervision layer

See `docs/elixir-cluster-daemon-review.md` for the code-quality review and the recommended hardening sequence.

## CLI surface

Representative commands:

```bash
cd elixir
mix claw control-plane-status
mix claw start-session --id smoke-session "review MCP tool"
mix claw submit-session smoke-session "review MCP tool"
mix claw session-status smoke-session
mix claw start-workflow smoke-flow "Update README" "Update docs"
mix claw workflow-status <workflow-id>
mix claw advance-task <workflow-id> task-1 completed "done"
```

## Verification

The current smoke/verification contract for the Elixir workspace is:

```bash
cd elixir
mix format --check-formatted
mix compile
mix test
```

Representative `mix claw` smoke checks should cover both the structural mirror and the control plane.
