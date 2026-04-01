# Rusty Claude CLI

`rust/` contains the Rust workspace for the integrated `rusty-claude-cli` deliverable.
It is intended to be something you can clone, build, and run directly.

## Workspace layout

```text
rust/
├── Cargo.toml
├── Cargo.lock
├── README.md
└── crates/
    ├── api/               # Anthropic API client + SSE streaming support
    ├── commands/          # Shared slash-command metadata/help surfaces
    ├── compat-harness/    # Upstream TS manifest extraction harness
    ├── runtime/           # Session/runtime/config/prompt orchestration
    ├── rusty-claude-cli/  # Main CLI binary
    └── tools/             # Built-in tool implementations
```

## Prerequisites

- Rust toolchain installed (`rustup`, stable toolchain)
- Network access and Anthropic credentials for live prompt/REPL usage

## Build

From the repository root:

```bash
cd rust
cargo build --release -p rusty-claude-cli
```

The optimized binary will be written to:

```bash
./target/release/rusty-claude-cli
```

## Test

Run the verified workspace test suite used for release-readiness:

```bash
cd rust
cargo test --workspace --exclude compat-harness
```

## Quick start

### Show help

```bash
cd rust
cargo run -p rusty-claude-cli -- --help
```

### Print version

```bash
cd rust
cargo run -p rusty-claude-cli -- --version
```

### Login with OAuth

Configure `settings.json` with an `oauth` block containing `clientId`, `authorizeUrl`, `tokenUrl`, optional `callbackPort`, and optional `scopes`, then run:

```bash
cd rust
cargo run -p rusty-claude-cli -- login
```

This opens the browser, listens on the configured localhost callback, exchanges the auth code for tokens, and stores OAuth credentials in `~/.claude/credentials.json` (or `$CLAUDE_CONFIG_HOME/credentials.json`).

### Logout

```bash
cd rust
cargo run -p rusty-claude-cli -- logout
```

This removes only the stored OAuth credentials and preserves unrelated JSON fields in `credentials.json`.

## Usage examples

### 1) Prompt mode

Send one prompt, stream the answer, then exit:

```bash
cd rust
cargo run -p rusty-claude-cli -- prompt "Summarize the architecture of this repository"
```

Use a specific model:

```bash
cd rust
cargo run -p rusty-claude-cli -- --model claude-sonnet-4-20250514 prompt "List the key crates in this workspace"
```

### 2) REPL mode

Start the interactive shell:

```bash
cd rust
cargo run -p rusty-claude-cli --
```

Inside the REPL, useful commands include:

```text
/help
/status
/model claude-sonnet-4-20250514
/permissions workspace-write
/cost
/compact
/memory
/config
/init
/exit
```

### 3) Resume an existing session

Inspect or maintain a saved session file without entering the REPL:

```bash
cd rust
cargo run -p rusty-claude-cli -- --resume session.json /status /compact /cost
```

You can also inspect memory/config state for a restored session:

```bash
cd rust
cargo run -p rusty-claude-cli -- --resume session.json /memory /config
```

## Available commands

### Top-level CLI commands

- `prompt <text...>` — run one prompt non-interactively
- `--resume <session.json> [/commands...]` — inspect or maintain a saved session
- `dump-manifests` — print extracted upstream manifest counts
- `bootstrap-plan` — print the current bootstrap skeleton
- `system-prompt [--cwd PATH] [--date YYYY-MM-DD]` — render the synthesized system prompt
- `--help` / `-h` — show CLI help
- `--version` / `-V` — print the CLI version and build info locally (no API call)
- `--output-format text|json` — choose non-interactive prompt output rendering
- `--allowedTools <tool[,tool...]>` — restrict enabled tools for interactive sessions and prompt-mode tool use

### Interactive slash commands

- `/help` — show command help
- `/status` — show current session status
- `/compact` — compact local session history
- `/model [model]` — inspect or switch the active model
- `/permissions [read-only|workspace-write|danger-full-access]` — inspect or switch permissions
- `/clear [--confirm]` — clear the current local session
- `/cost` — show token usage totals
- `/resume <session-path>` — load a saved session into the REPL
- `/config [env|hooks|model]` — inspect discovered Claude config
- `/memory` — inspect loaded instruction memory files
- `/init` — create a starter `CLAUDE.md`
- `/exit` — leave the REPL

## Environment variables

### Anthropic/API

- `ANTHROPIC_API_KEY` — highest-precedence API credential
- `ANTHROPIC_AUTH_TOKEN` — bearer-token override used when no API key is set
- Persisted OAuth credentials in `~/.claude/credentials.json` — used when neither env var is set
- `ANTHROPIC_BASE_URL` — override the Anthropic API base URL
- `ANTHROPIC_MODEL` — default model used by selected live integration tests

### CLI/runtime

- `RUSTY_CLAUDE_PERMISSION_MODE` — default REPL permission mode (`read-only`, `workspace-write`, or `danger-full-access`)
- `CLAUDE_CONFIG_HOME` — override Claude config discovery root
- `CLAUDE_CODE_REMOTE` — enable remote-session bootstrap handling when supported
- `CLAUDE_CODE_REMOTE_SESSION_ID` — remote session identifier when using remote mode
- `CLAUDE_CODE_UPSTREAM` — override the upstream TS source path for compat-harness extraction
- `CLAWD_WEB_SEARCH_BASE_URL` — override the built-in web search service endpoint used by tooling

## Notes

- `compat-harness` exists to compare the Rust port against the upstream TypeScript codebase and is intentionally excluded from the requested release test run.
- The CLI currently focuses on a practical integrated workflow: prompt execution, REPL operation, session inspection/resume, config discovery, and tool/runtime plumbing.
