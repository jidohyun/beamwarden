# Elixir Cluster Daemon Review

This note reflects the repository state after the daemon-oriented hardening pass on April 1, 2026.

## What is shipped now

The Elixir control plane is no longer only an ephemeral CLI wrapper around local supervisors.

It now ships:

- a dedicated `Beamwarden.DaemonSupervisor` root boundary
- a supervised `Beamwarden.ClusterDaemon` ownership ledger backed by DETS
- `Beamwarden.DaemonNodeMonitor` reconciliation on node membership changes
- daemon-aware CLI proxying through `BEAMWARDEN_DAEMON_NODE` with `CLAW_*` compatibility fallbacks
- longname-aware daemon/client startup for cross-host operation when the daemon host uses an FQDN
- daemon-first routing for new session/workflow work handled on the configured server node
- distributed ExUnit coverage proving that one client can create session state through the daemon and another client can inspect the same state without depending on the first client process surviving

The runtime still keeps the existing `claw_code_daemon` / `claw_code_cli` node labels in this slice so cross-node operator workflows do not break during the rename transition.

## What improved in the three hardening slices

### 1. Ownership / failover hardening

- Ownership is now tracked in the cluster ledger, not only in the snapshot JSON.
- The ledger stores epoch/lease-style metadata and is consulted before falling back to persisted owner strings.
- Running owners still win first, which keeps live routing stable.

### 2. Durable daemon mode beyond shared JSON

- Active routing continuity can now go through a long-running daemon node instead of depending on every CLI invocation spinning up its own isolated control plane.
- Ownership metadata survives daemon restarts through the DETS-backed ledger.
- Client nodes can proxy CLI control-plane calls to the configured daemon node.

### 3. Stronger long-running supervision tree

- `Beamwarden.Application` now boots a dedicated daemon/root supervisor.
- Cluster services and control-plane services are supervised under explicit daemon-oriented boundaries instead of living as a flat one-off CLI tree.
- Node monitoring and reconciliation are now first-class services.

## Honest limits that remain

The implementation is materially stronger, but it is still intentionally conservative:

- quorum/failover is still **best-effort across connected BEAM nodes**; there is no external consensus system
- session/workflow payload durability still relies on JSON snapshots
- cluster discovery is still limited to BEAM nodes that can already connect to each other
- operators must still coordinate cookies and choose matching shortname/longname mode explicitly across hosts
- `cluster-connect` / `cluster-disconnect` still require a distributed VM

## Verification contract

```bash
cd elixir
mix format --check-formatted
mix compile
mix test
```
