# Elixir Multi-node OTP Control-Plane Design

## Recommended direction
Use built-in BEAM distribution primitives instead of adding dependencies.

### Core pieces
- `Cluster` / `NodeManager` module for node naming, connection, membership, and health reporting
- distributed process grouping via `:pg`
- per-node supervisors for sessions/workflows
- routing helpers that can inspect which node owns a session/workflow
- cluster-aware CLI/status commands
- local distributed tests using OTP's built-in peer-node capabilities where available

## Why this fits Elixir
This makes Elixir more than a metadata mirror: it becomes the repo's actual orchestration/control-plane runtime, while Rust remains the low-level execution reference.

## Guardrails
- No new dependencies
- Honest docs: multi-node capable, not production cluster management
- Preserve existing single-node flows
