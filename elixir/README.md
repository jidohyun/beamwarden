# Elixir Structural Mirror for claw-code

`elixir/` is the primary Mix-based workspace for this repository. It preserves the clean-room mirror strategy established by the Python layer, but packages the active developer-facing surface as a Mix/OTP application.

It is intentionally **not** a full runtime-equivalent reimplementation of Claude Code. Instead, it currently ships:

- snapshot-backed command and tool inventories
- manifest and parity-audit reporting
- setup/bootstrap summaries
- routing and synthetic turn-loop behavior
- session persistence and permission filtering
- OTP-native supervised sessions plus persisted workflow/task orchestration
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
mix claw start-session --id smoke-session "review MCP tool"
mix claw submit-session smoke-session "review MCP tool"
mix claw start-workflow smoke-flow "Update README" "Update docs"
```

## Inventory and placeholder surfaces

This workspace follows the same conservative porting approach as the Python tree, while now taking ownership of the repository's primary orchestration surface:

- it reuses `reference/python/src/reference_data/*.json`
- it mirrors structure and control flow
- it adds Mix/OTP-native supervision for sessions and workflows
- it does **not** claim full Claude Code runtime parity

Python and Rust remain in the repository as companion/reference subtrees (`reference/python/`, `reference/rust/`) rather than the primary workspace.
