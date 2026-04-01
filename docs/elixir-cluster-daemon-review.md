# Elixir Cluster Daemon Review

This review documents the current Elixir multi-node control plane as of April 1, 2026 and maps the remaining work needed to turn it into a more durable cluster daemon without adding non-OTP dependencies.

## Current baseline

The current control plane is already useful, but it is still **session/workflow supervision inside an otherwise short-lived CLI VM**, not a durable daemon:

- `ClawCode.Application` starts local registries plus dynamic supervisors only (`elixir/lib/claw_code/application.ex:6-14`).
- Session/workflow ownership is resolved with the runtime owner first, then a persisted owner string from JSON, then a `:erlang.phash2/2` fallback (`elixir/lib/claw_code/control_plane.ex:6-119`, `elixir/lib/claw_code/cluster.ex:12-19`).
- Durable state is still JSON-backed for both sessions and workflows (`elixir/lib/claw_code/session_store.ex:11-25`, `elixir/lib/claw_code/workflow_store.ex:4-17`).
- Session/workflow workers are `restart: :transient`, which is appropriate for the current CLI-shaped lifecycle but not sufficient for a long-running daemon story (`elixir/lib/claw_code/session_server.ex:15-20`, `elixir/lib/claw_code/workflow_server.ex:8-13`).

That means the current implementation is best described as **distributed routing plus resumable local workers**, not yet quorum-backed cluster process management.

## Review by strengthening slice

### 1. Quorum and ownership failover hardening

**What exists now**

- Ownership metadata is a single `owner_node` string in the persisted snapshot (`elixir/lib/claw_code/session_store.ex:15-21`, `elixir/lib/claw_code/workflow_store.ex:4-8`).
- Failover is effectively “if the running owner is gone, try the persisted owner, then hash across connected members” (`elixir/lib/claw_code/cluster.ex:89-99` and the README routing summary).

**Why that is not durable enough yet**

- There is no term/epoch, lease, fencing token, or quorum acknowledgement attached to ownership.
- Two nodes that can both see the same JSON snapshot can both decide they should resume it.
- `list_sessions/0` and `list_workflows/0` merge per-node answers for reporting, but that is observation, not conflict prevention (`elixir/lib/claw_code/control_plane.ex:121-140`).

**Recommended next hardening step**

Stay inside built-in OTP/BEAM primitives:

1. introduce an ownership record with `owner_node`, `owner_term`, `observed_at`, and `origin`;
2. gate adoption behind an explicit cluster-wide claim/ack round (`:rpc.multicall/4` or `:global.trans/4`);
3. only allow takeover when the previous owner is unreachable and no higher/equal term claim is present.

**Honest limit**

Without a consensus system or an external durable log, this can become *safer* but not fully partition-proof. Docs should keep calling it best-effort across connected BEAM nodes.

### 2. Durable cluster daemon mode without relying only on shared JSON

**What exists now**

- Active continuity still depends on restarting from snapshot files.
- Session/workflow discovery uses local registries plus RPC fan-out, which works only while participating nodes are already running (`elixir/lib/claw_code/control_plane.ex:121-140`, `elixir/lib/claw_code/control_plane.ex:224-245`).

**Why that is not durable enough yet**

- Shared JSON is the durable handoff layer today; there is no long-running cluster coordinator process that outlives one `mix claw ...` invocation.
- The cluster status output already documents this limitation explicitly (`elixir/lib/claw_code/cluster.ex:102-123`).

**Recommended next hardening step**

Build a daemon mode where:

1. a long-running named BEAM node hosts a cluster coordinator process;
2. registries/supervisors become the primary live state;
3. JSON snapshots remain recovery artifacts, not the primary cross-node coordination path;
4. CLI commands talk to the daemon node instead of spinning up isolated control-plane state for every invocation.

**Honest limit**

If the daemon is not running, the system should fall back to the current single-node CLI behavior rather than pretend cluster continuity still exists.

### 3. Stronger long-running daemon supervision tree

**What exists now**

- The root supervisor is flat and intentionally small: session registry/supervisor plus workflow registry/supervisor only (`elixir/lib/claw_code/application.ex:6-14`).
- Session and workflow workers are individually restartable, but there is no dedicated cluster coordinator, node monitor, adoption service, or daemon-facing command bridge.

**Why that is not durable enough yet**

- There is no supervision boundary dedicated to cluster lifecycle.
- Worker restart semantics are tuned for ephemeral CLI execution, not for persistent daemon service ownership.

**Recommended next hardening step**

Move toward a tree shaped more like:

1. `ClawCode.DaemonSupervisor`
2. `ClawCode.ClusterSupervisor`
3. node monitor / ownership coordinator / adoption service
4. session + workflow supervisors under that cluster layer

This keeps today’s single-node workers intact while making cluster lifecycle explicit and reviewable.

## Code-quality summary

The current design is coherent and conservative:

- it preserves single-node behavior;
- it uses only OTP/BEAM built-ins;
- it keeps the current routing rules easy to understand;
- it already documents some limitations honestly.

The main quality risk is **overstating durability**. The code is not pretending to solve consensus, but the docs needed a clearer distinction between:

- resumable supervision,
- distributed routing,
- durable daemon behavior.

## Documentation stance to keep

Use this phrasing consistently:

- **Shipped today:** resumable OTP sessions/workflows with distributed routing across connected nodes.
- **Not shipped yet:** quorum-backed ownership, daemon-first coordination, partition-safe failover, and cluster continuity without an already-running distributed node.

## Verification note

This review is documentation-only. The repository verification contract remains:

```bash
cd elixir
mix format --check-formatted
mix compile
mix test
```
