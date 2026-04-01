# Rust Reference Subtree

`reference/rust/` is retained as a runtime-oriented companion subtree, not the repository's primary workspace.

Use it when you need:

- a deeper executable comparison point for prompt building, permissions, MCP plumbing, OAuth, and low-level tools
- the preserved Cargo workspace for `rusty-claude-cli`
- Rust-specific verification or experimentation that complements the Elixir-first surface

Primary repository docs, coordination, and verification now live under `elixir/`.

## Workspace outline

```text
reference/rust/
├── Cargo.toml
├── Cargo.lock
├── crates/
│   ├── api
│   ├── commands
│   ├── compat-harness
│   ├── runtime
│   ├── rusty-claude-cli
│   └── tools
└── README.md
```

## Representative checks

```bash
cd reference/rust
cargo build --release -p rusty-claude-cli
cargo test --workspace --exclude compat-harness
```

## Representative commands

```bash
cd reference/rust
cargo run -p rusty-claude-cli -- --help
cargo run -p rusty-claude-cli -- prompt "Summarize the architecture of this repository"
cargo run -p rusty-claude-cli -- --resume session.json /status /compact /cost
```

## Notes

- OAuth/login flows still use the Rust CLI's own credential/config handling.
- `compat-harness` remains the upstream-manifest comparison crate and is still excluded from the standard workspace test command above.
- Prefer changing Elixir docs/control-plane behavior first unless you are explicitly working inside this Rust reference subtree.
