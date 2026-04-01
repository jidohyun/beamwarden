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
- it adds Mix/OTP-native supervision for sessions, workflows, and a durable cluster daemon subtree
- it can route session/workflow operations across connected BEAM nodes without extra dependencies
- it does **not** claim full Claude Code runtime parity

## Distributed control-plane notes

The Elixir control plane now routes sessions and workflows with this priority:

1. currently running owner node
2. the supervised cluster daemon's replicated ownership ledger (quorum gated across the connected BEAM subcluster)
3. persisted owner node recorded in the JSON snapshot
4. a `:erlang.phash2/2` fallback across the currently connected cluster members

The daemon persists its ledger to a per-node DETS file under `.port_sessions/cluster/<node>/ledger.dets` and fan-outs ownership updates over BEAM RPC, so cross-node routing does not rely only on shared JSON snapshots.

This keeps single-node behavior unchanged while allowing local multi-node tests and distributed embeddings to coordinate through the same APIs.

Current status: this is **distributed routing plus resumable OTP workers**, not yet a durable cluster daemon. The most current review note is in `../docs/elixir-cluster-daemon-review.md`.

### What is solid today

- connected BEAM nodes can route control-plane actions to a live owner node
- sessions and workflows can be resumed from persisted snapshots
- the OTP supervision layer is real and test-covered
- single-node `mix claw ...` flows remain intact

### What still needs to happen for a durable daemon

1. harden ownership/failover beyond a single persisted `owner_node` string
2. make a long-running daemon node the primary live coordination path
3. introduce a stronger supervision tree for cluster coordination services

Honest limits:

- `mix claw ...` is still an ephemeral CLI entrypoint; it does **not** keep an always-on cluster alive after the command exits unless you run the VM itself as a long-lived node.
- `cluster-connect` / `cluster-disconnect` only work when the current VM is already distributed (`--sname`, `--name`, or `Node.start/2`).
- Quorum is based on the currently connected BEAM subcluster only; there is still no external consensus store or split-brain resolution beyond what the connected nodes can observe.
- Session/workflow contents still resume from JSON snapshots, so durable routing metadata is stronger than durable payload storage when nodes do not share the same filesystem.

Python and Rust remain in the repository as companion/reference subtrees (`reference/python/`, `reference/rust/`) rather than the primary workspace or a required Mix build input.
