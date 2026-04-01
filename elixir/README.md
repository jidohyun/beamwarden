# Claw Code — Elixir Workspace

This is now the primary implementation workspace for the repository.

`elixir/` is a clean-room structural mirror of the Claude Code surface, but it is no longer only a local OTP wrapper around one-off CLI commands. It now includes a **daemon-first control plane** for connected BEAM nodes:

- copied mirror data under `priv/reference_data/`
- supervised session/workflow processes
- a supervised cluster daemon with a DETS-backed ownership ledger
- daemon-aware CLI proxying through a configured long-running BEAM node
- multi-node ExUnit coverage for routing, failover, durability, and daemon-mode continuity

It still does **not** claim full Claude Code runtime parity.

## Distributed control-plane notes

The Elixir control plane now routes sessions and workflows with this priority:

1. currently running owner node
2. the supervised cluster daemon's replicated ownership ledger
3. the configured daemon node when commands are being served from daemon mode
4. persisted owner node recorded in the JSON snapshot
5. a `:erlang.phash2/2` fallback across the currently connected cluster members

The daemon persists ownership metadata to a per-node DETS file under `.port_sessions/cluster/<node>/ledger.dets` and fans ownership updates out over BEAM RPC, so routing continuity no longer depends only on shared JSON snapshots.

## Daemon mode

Run a long-lived daemon node:

```bash
cd elixir
mix claw daemon-run --name claw_code_daemon
```

Talk to it from another shell:

```bash
cd elixir
CLAW_DAEMON_NODE=claw_code_daemon@$(hostname -s) mix claw daemon-status
CLAW_DAEMON_NODE=claw_code_daemon@$(hostname -s) mix claw start-session --id smoke-session "review MCP tool"
CLAW_DAEMON_NODE=claw_code_daemon@$(hostname -s) mix claw session-status smoke-session
```

Representative local commands:

```bash
cd elixir
mix claw summary
mix claw manifest
mix claw control-plane-status
mix claw cluster-status
mix claw start-workflow smoke-flow "Update README" "Update docs"
mix claw workflow-status smoke-flow
```

## Honest limits

- Quorum/failover is still best-effort across the currently connected BEAM subcluster; there is no external consensus store.
- Session/workflow payloads still recover from JSON snapshots, so daemon durability is stronger for ownership/routing than for payload storage.
- `cluster-connect` / `cluster-disconnect` still require the current VM to be distributed (`--sname`, `--name`, or `Node.start/2`).

Python and Rust remain in the repository as companion/reference subtrees (`reference/python/`, `reference/rust/`).
