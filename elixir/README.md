# Elixir Structural Mirror for claw-code

`elixir/` is the primary Mix-based workspace for this repository. It preserves the clean-room mirror strategy established by the Python layer, but packages the active developer-facing surface as a Mix/OTP application.

It is intentionally **not** a full runtime-equivalent reimplementation of Claude Code. Instead, it currently ships:

- Elixir-owned copied snapshot-backed command and tool inventories
- manifest and parity-audit reporting
- setup/bootstrap summaries
- routing and synthetic turn-loop behavior
- session persistence and permission filtering
- OTP-native supervised sessions plus persisted workflow/task orchestration
- multi-node aware control-plane routing using built-in BEAM distribution only
- ExUnit coverage for the mirrored CLI surface

## Verification

```bash
cd elixir
mix format --check-formatted
mix compile
mix test
```

## Representative smoke checks

```bash
cd elixir
mix claw summary
mix claw manifest
mix claw setup-report
mix claw bootstrap "review MCP tool"
mix claw control-plane-status
mix claw cluster-status
mix claw start-session --id smoke-session "review MCP tool"
mix claw submit-session smoke-session "review MCP tool"
mix claw start-workflow smoke-flow "Update README" "Update docs"
```

## Inventory and placeholder surfaces

This workspace follows the same conservative porting approach as the Python tree, while now taking ownership of the repository's primary orchestration surface:

- it keeps its own copied reference snapshots under `priv/reference_data/`
- it mirrors structure and control flow
- it adds Mix/OTP-native supervision for sessions and workflows
- it can route session/workflow operations across connected BEAM nodes without extra dependencies
- it does **not** claim full Claude Code runtime parity

## Distributed control-plane notes

The Elixir control plane now routes sessions and workflows with this priority:

1. currently running owner node
2. persisted owner node recorded in the JSON snapshot
3. a `:erlang.phash2/2` fallback across the currently connected cluster members

This keeps single-node behavior unchanged while allowing local multi-node tests and distributed embeddings to coordinate through the same APIs.

Honest limits:

- `mix claw ...` is still an ephemeral CLI entrypoint; it does **not** leave behind a daemonized cluster after the command exits.
- `cluster-connect` / `cluster-disconnect` only work when the current VM is already distributed (`--sname`, `--name`, or `Node.start/2`).
- Ownership failover is best-effort. If the previous owner node is unavailable, another connected node can adopt the persisted snapshot, but there is no quorum or conflict-resolution layer.
- Persisted snapshots assume shared filesystem visibility when you expect multiple nodes to resume the same session/workflow JSON.

Python and Rust remain in the repository as companion/reference subtrees (`reference/python/`, `reference/rust/`) rather than the primary workspace or a required Mix build input.
