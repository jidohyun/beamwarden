# Elixir Daemon Operations Guide

This guide documents the current daemon-first control-plane workflow in two modes:

1. **single-host smoke tests** using `mix beamwarden daemon-run`
2. **cross-host daemon/client operation** using explicit longnames and a shared cookie

The current daemon bootstrap supports both:

- local shortname smoke tests via `mix beamwarden daemon-run`
- longname-aware startup via `mix beamwarden daemon-run --longname`

For more controlled production-like operation, you can still prestart the BEAM VM yourself with `--name` / `--cookie` and then boot the daemon inside that already-distributed node.

## 1. Local single-host smoke test

Use this when the daemon and clients are running on the same machine:

```bash
cd elixir
BEAMWARDEN_DAEMON_COOKIE=clawcluster mix beamwarden daemon-run --name claw_code_daemon --cookie clawcluster
```

From another shell on the same host:

```bash
cd elixir
export BEAMWARDEN_DAEMON_NODE=claw_code_daemon@$(hostname -s)
export BEAMWARDEN_DAEMON_COOKIE=clawcluster

mix beamwarden daemon-status
mix beamwarden start-session --id smoke-session "review MCP tool"
mix beamwarden session-status smoke-session
```

Notes:

- use the same cookie on every node that should connect to the daemon
- keep all nodes on either shortnames or longnames; BEAM nodes cannot mix the two naming modes
- `cluster-connect` / `cluster-disconnect` still require an already distributed VM

## 2. Cross-host longname + cookie flow

Use longnames when the daemon and clients live on different hosts or when you want an explicit routable node identity.

Assumptions for the examples below:

- daemon host FQDN: `daemon1.example.com`
- client host FQDN: `client1.example.com`
- daemon node name: `claw_code_daemon@daemon1.example.com`
- shared cookie: `clawcluster`

### Step 1: start the daemon host with a longname

```bash
cd elixir
BEAMWARDEN_DAEMON_COOKIE=clawcluster mix beamwarden daemon-run --name claw_code_daemon --longname
```

At this point the daemon ledger should be live under `.port_sessions/cluster/<node>/ledger.dets`.

### Step 2: start a client VM on another host with the same cookie

```bash
cd elixir
export BEAMWARDEN_DAEMON_NODE=claw_code_daemon@daemon1.example.com
export BEAMWARDEN_DAEMON_COOKIE=clawcluster
export BEAMWARDEN_DAEMON_NAME_MODE=longnames

mix beamwarden daemon-status
mix beamwarden start-session --id smoke-session "review MCP tool"
```

Expected daemon status indicators:

- `role=client` or `role=standalone` if the daemon is unreachable and the client falls back locally
- `configured_daemon_node=claw_code_daemon@daemon1.example.com`
- `daemon_reachable=true`

Expected session output indicator:

- `owner_node=claw_code_daemon@daemon1.example.com`

### Step 3: inspect the same session from another client host

Any other client node that starts with a longname and the same cookie can point at the same daemon:

```bash
cd elixir
export BEAMWARDEN_DAEMON_NODE=claw_code_daemon@daemon1.example.com
export BEAMWARDEN_DAEMON_COOKIE=clawcluster
export BEAMWARDEN_DAEMON_NAME_MODE=longnames

mix beamwarden session-status smoke-session
```

That proves the active control plane is going through the long-running daemon node rather than depending on the original client shell staying alive.

## Best-effort failover behavior

The daemon-first control plane is intentionally conservative:

- routing first prefers a currently running owner
- otherwise it consults the daemon ledger quorum view
- then it falls back to reachable persisted ownership metadata
- finally it uses deterministic `:erlang.phash2/2` routing across connected members

If `BEAMWARDEN_DAEMON_NODE` is configured but unreachable, proxyable CLI commands fall back to local execution instead of crashing. `mix beamwarden daemon-status` (or `Beamwarden.CLI.run(["daemon-status"])`) will show `daemon_reachable=false` in that case. The older `CLAW_*` env vars and `mix claw ...` remain available as compatibility fallbacks.

## Current limits

- there is still no external consensus or split-brain-safe quorum system
- payload durability still relies on JSON snapshots even though active ownership continuity now lives in the daemon ledger
- cluster discovery is still limited to BEAM nodes that can already connect to each other
