# Elixir Structural Mirror for claw-code

`elixir/` is a Mix-based Elixir porting workspace that mirrors the current Python port strategy used in this repository.

It is intentionally **not** a full runtime-equivalent reimplementation of Claude Code. Instead, it preserves:

- snapshot-backed command and tool inventories
- manifest and parity-audit reporting
- setup/bootstrap summaries
- routing and synthetic turn-loop behavior
- session persistence and permission filtering
- ExUnit coverage for the mirrored CLI surface

## Verification

```bash
cd elixir
mix format --check-formatted
mix compile
mix test
```

## CLI

```bash
cd elixir
mix claw summary
mix claw manifest
mix claw parity-audit
mix claw bootstrap "review MCP tool"
```

## Scope

This workspace follows the same conservative porting approach as the Python tree:

- it reuses `src/reference_data/*.json`
- it mirrors structure and control flow
- it does **not** claim full Claude Code runtime parity

For deeper executable runtime behavior, this repository still leans on the Rust workspace under `rust/`.
