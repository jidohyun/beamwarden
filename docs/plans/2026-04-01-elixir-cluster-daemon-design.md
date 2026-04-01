# Elixir Cluster Daemon Design

## Chosen direction
Move from ephemeral CLI orchestration toward a durable OTP-native cluster daemon with clearer ownership semantics.

## Sequential implementation slices
1. **Ownership/failover hardening**
   - explicit owner tracking
   - safer node identity handling
   - re-adoption/failover semantics stronger than current best-effort routing
2. **Durable distributed state**
   - reduce shared JSON dependence for active cluster continuity
   - use long-running OTP processes/registries as primary runtime state, with persisted snapshots as secondary support
3. **Daemon supervision**
   - dedicated daemon/root supervisor tree for cluster coordinator(s)
   - background control-plane services that outlive one-off CLI command execution

## Guardrails
- No new dependencies
- Honest docs about what is and is not production-grade
- Preserve the current Mix workflow and single-node behavior while adding daemon mode
