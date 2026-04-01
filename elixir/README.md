# Elixir Structural Mirror for claw-code

`elixir/` is the primary developer workspace for this repository. It packages the clean-room mirror as a Mix/BEAM project while Python and Rust remain companion/reference layers.

It is intentionally **not** a full runtime-equivalent reimplementation of Claude Code. Instead, it currently ships:

- snapshot-backed command and tool inventories
- manifest, parity-audit, setup, command-graph, and tool-pool reporting
- routing, bootstrap, and synthetic turn-loop smoke checks
- session persistence plus transcript flush/load commands
- supervised session/workflow control-plane helpers
- remote/direct mode placeholder commands
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
mix claw turn-loop "review MCP tool" --max-turns 2 --structured-output
mix claw session-start demo-session
mix claw session-submit demo-session "review MCP tool"
mix claw workflow-start demo-flow
mix claw workflow-add-step demo-flow "bootstrap session"
```

## Inventory and placeholder surfaces

```bash
cd elixir
mix claw commands --limit 10
mix claw tools --limit 10
mix claw command-graph
mix claw tool-pool
mix claw remote-mode workspace
mix claw direct-connect-mode workspace
```

## Scope and current control-plane status

This workspace follows the same conservative porting approach as the earlier Python tree:

- it reuses `src/reference_data/*.json`
- it mirrors structure and control flow
- it persists sessions and exposes lightweight OTP control-plane primitives
- it does **not** yet claim full Claude Code runtime parity

For deeper executable runtime behavior, this repository still leans on the Rust workspace under `rust/`.

Read `../docs/elixir-first-review.md` and `../docs/plans/2026-04-01-elixir-control-plane-design.md` for the current review and roadmap.
