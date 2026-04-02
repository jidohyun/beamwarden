# Beamwarden — Elixir Workspace

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
mix beamwarden daemon-run --name beamwarden_daemon
# add --longname for cross-host / FQDN operation
```

Talk to it from another shell:

```bash
cd elixir
BEAMWARDEN_DAEMON_NODE=beamwarden_daemon@$(hostname -s) mix beamwarden daemon-status
BEAMWARDEN_DAEMON_NODE=beamwarden_daemon@$(hostname -s) mix beamwarden start-session --id smoke-session "review MCP tool"
BEAMWARDEN_DAEMON_NODE=beamwarden_daemon@$(hostname -s) mix beamwarden session-status smoke-session
```

If the daemon node uses a fully-qualified host (for example `beamwarden_daemon@daemon.example.internal`), run both the daemon and clients in longname mode:

```bash
# daemon host
BEAMWARDEN_DAEMON_COOKIE=clawsecret mix beamwarden daemon-run --name beamwarden_daemon --longname

# remote client
BEAMWARDEN_DAEMON_NODE=beamwarden_daemon@daemon.example.internal \
BEAMWARDEN_DAEMON_COOKIE=clawsecret \
BEAMWARDEN_DAEMON_NAME_MODE=longnames \
mix beamwarden daemon-status
```

Use the same cookie on every participating node. Shortname mode remains the default for local/same-host workflows.

Representative local commands:

```bash
cd elixir
mix beamwarden summary
mix beamwarden manifest
mix beamwarden control-plane-status
mix beamwarden cluster-status
mix beamwarden start-workflow smoke-flow "Update README" "Update docs"
mix beamwarden workflow-status smoke-flow
```

## Honest limits

Implementation references for these limits:

- supervision tree: `lib/beamwarden/application.ex`
- routing/failover: `lib/beamwarden/control_plane.ex`, `lib/beamwarden/cluster.ex`
- persisted ownership: `lib/beamwarden/session_store.ex`, `lib/beamwarden/workflow_store.ex`

Implementation references for these limits:

- supervision tree: `lib/beamwarden/application.ex`
- routing/failover: `lib/beamwarden/control_plane.ex`, `lib/beamwarden/cluster.ex`
- persisted ownership: `lib/beamwarden/session_store.ex`, `lib/beamwarden/workflow_store.ex`

Python and Rust remain in the repository as companion/reference subtrees (`reference/python/`, `reference/rust/`) rather than the primary workspace or a required Mix build input.
