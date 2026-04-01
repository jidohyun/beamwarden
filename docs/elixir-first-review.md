# Elixir-first Review and Control-Plane Notes

This note captures the repository's current Elixir-first state after the control-plane push.

## What is shipped today

The main developer workflow now runs through `elixir/`:

```bash
cd elixir
mix format --check-formatted
mix compile
mix test
```

The `mix claw` surface now covers four practical groups:

1. **Reporting and inventory**
   - `summary`
   - `manifest`
   - `parity-audit`
   - `setup-report`
   - `bootstrap-graph`
   - `command-graph`
   - `tool-pool`
2. **Routing / bootstrap smoke checks**
   - `route <prompt>`
   - `bootstrap <prompt>`
   - `turn-loop <prompt> [--max-turns ...] [--structured-output]`
3. **Session persistence and OTP control-plane helpers**
   - `flush-transcript <prompt>`
   - `load-session <session_id>`
   - `session-start <session_id>`
   - `session-submit <session_id> <prompt>`
   - `session-status <session_id>`
   - `workflow-start <workflow_id>`
   - `workflow-add-step <workflow_id> <title>`
   - `workflow-complete-step <workflow_id> <step_id>`
   - `workflow-status <workflow_id>`
4. **Placeholder remote/direct mode reports**
   - `remote-mode <target>`
   - `ssh-mode <target>`
   - `teleport-mode <target>`
   - `direct-connect-mode <target>`
   - `deep-link-mode <target>`

## Strengths

- **Elixir is now the primary verified workspace.** The main verification loop is Mix-native and green.
- **Elixir owns its snapshot inputs.** Mirrored command/tool/archive reference data now lives under `elixir/priv/reference_data`, so the active workspace no longer depends on `reference/python/` for checked-in inventories.
- **The structural mirror is broad.** The Elixir tree now covers the missing Python-root concepts such as query/task/tool/repl/cost/onboarding helper modules.
- **A real OTP control-plane slice exists.** `ClawCode.ControlPlane`, `SessionServer`, and `WorkflowServer` demonstrate supervised session/workflow behavior instead of documentation-only claims.
- **CLI/tests stay aligned.** The ExUnit suite covers both the structural mirror and the control-plane commands.

## Honest limits

- The control plane is still lightweight and local-first. It is not yet a clustered, long-lived orchestration runtime.
- Most mirrored command/tool behavior is still descriptive shim execution rather than full Claude Code equivalence.
- Rust remains the deeper runtime path for low-level execution concerns, but now as a reference subtree instead of an active primary workspace.

## Suggested reviewer smoke checks

```bash
cd elixir
mix format --check-formatted
mix compile
mix test
mix claw bootstrap "review MCP tool"
mix claw session-submit review-session "review MCP tool"
mix claw workflow-add-step review-flow "bootstrap session"
```
