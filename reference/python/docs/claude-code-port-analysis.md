# Claude Code → Python Port Analysis

> Historical note: these paths were written when the Python companion lived at the repo root and a Rust reference subtree still existed in-tree. The Python mirror now lives under `reference/python/`. The Rust subtree has since been removed from Beamwarden, so any Rust paths below are archival references only.

This note now documents the Python companion layer. The repository itself is Elixir-first, with `elixir/` as the primary workspace and `src/` retained as a historical/reference mirror.

## 1. CLI / runtime architecture mapping

### README establishes the porting target
- `README.md:66-74` says the repository is now **Python-first**, with `src/` as the active porting workspace and `tests/` as verification.
- `README.md:151-153` explicitly says the port mirrors the archived root-entry surface, subsystem names, and command/tool inventories, but is **not yet runtime-equivalent** with the original TypeScript system.

### TypeScript entry surface is mapped into Python files and packages
- `src/parity_audit.py:13-32` hard-codes the root-file mapping from archived TS files to Python targets, including:
  - `main.tsx -> main.py`
  - `QueryEngine.ts -> QueryEngine.py`
  - `commands.ts -> commands.py`
  - `tools.ts -> tools.py`
  - `setup.ts -> setup.py`
  - `replLauncher.tsx -> replLauncher.py`
- `src/parity_audit.py:34-70` mirrors top-level TS directories into Python packages (`assistant`, `bridge`, `cli`, `hooks`, `remote`, `services`, `utils`, etc.).

### The Python CLI is a mirror-oriented harness, not a full live agent CLI
- `src/main.py:21-90` defines the Python CLI surface: `summary`, `manifest`, `parity-audit`, `commands`, `tools`, `route`, `bootstrap`, `turn-loop`, `load-session`, and runtime-mode shims.
- `src/main.py:94-207` dispatches those commands into manifest rendering, snapshot-backed routing, simulated runtime sessions, session persistence, and placeholder remote/direct modes.
- Evidence from `python3 -m src.main manifest`:
  - current workspace reports **66 Python files**.
- Evidence from `python3 -m src.main bootstrap 'review MCP tool' --limit 5`:
  - startup loads **207 command entries** and **184 tool entries**.

### Runtime control flow is recreated as a lightweight Python orchestration pipeline
- `src/runtime.py:109-152` shows the central boot path:
  1. build workspace context
  2. run setup/prefetch
  3. build history
  4. route prompt over mirrored command/tool inventories
  5. execute mirrored command/tool shims
  6. stream a turn through `QueryEnginePort`
  7. persist the session
- `src/bootstrap_graph.py:13-23` summarizes the intended Claude-Code-like boot order: prefetch side effects, trust gate, setup, mode routing, and query-engine submit loop.
- `src/setup.py:19-27` and `src/setup.py:64-77` show the Python startup contract: prefetches + parity hooks + trust-gated deferred init.
- `src/prefetch.py:14-23` and `src/deferred_init.py:23-31` make clear these are currently simulated bootstrap effects, not production integrations.

## 2. SDK, prompt, tools, permissions, and control-flow porting

### Commands and tools are ported primarily as mirrored inventories
- `src/commands.py:22-36` loads `src/reference_data/commands_snapshot.json` into `PORTED_COMMANDS`.
- `src/tools.py:23-37` loads `src/reference_data/tools_snapshot.json` into `PORTED_TOOLS`.
- The snapshots currently contain:
  - **207 command entries** (`src/reference_data/commands_snapshot.json`)
  - **184 tool entries** (`src/reference_data/tools_snapshot.json`)
- `src/commands.py:75-80` and `src/tools.py:81-86` show that execution is still shim-based: they emit "Mirrored command/tool ... would handle ..." messages rather than invoking a live Claude runtime.

### Prompt routing is inventory-driven
- `src/runtime.py:89-107` tokenizes the prompt and scores both mirrored commands and mirrored tools.
- Evidence from `python3 -m src.main route 'review MCP tool' --limit 5`:
  - command match: `UltrareviewOverageDialog`
  - tool matches: `ListMcpResourcesTool`, `MCPTool`, `McpAuthTool`, `ReadMcpResourceTool`
- This means the current Python port preserves Claude Code's *selection surface* more than its original execution semantics.

### Query engine and conversation loop are simplified into a synthetic Python runtime
- `src/query_engine.py:15-21` defines max turns, budget, compaction, and structured-output retries.
- `src/query_engine.py:61-104` builds `TurnResult` objects from matched commands/tools and permission denials.
- `src/query_engine.py:106-127` emits stream-style events (`message_start`, `command_match`, `tool_match`, `message_delta`, `message_stop`).
- `src/query_engine.py:140-149` persists local sessions through `session_store.py`.
- `src/session_store.py:14-28` stores sessions as JSON files under `.port_sessions/`.
- `src/transcript.py:8-20` implements transcript append/compact/flush behavior.

### Prompt/system-init porting is summarized rather than fully synthesized in Python
- `src/system_init.py:8-22` builds a startup message from trust state plus loaded command/tool counts.
- Unlike the Rust port, the Python tree does **not** contain a full system-prompt builder or live Anthropic request pipeline.

### Permission handling is present, but lightweight
- `src/permissions.py:6-20` supports deny-by-name and deny-by-prefix filtering.
- `src/tools.py:56-72` applies that permission context to the mirrored tool list.
- `src/runtime.py:169-174` injects a specific denial when a routed tool name contains `bash`, so destructive shell execution remains gated in the Python port.
- Evidence from `python3 -m src.main tools --limit 8 --deny-prefix mcp`:
  - tool count falls from **184** to **182**, confirming prefix-based filtering works.

## 3. Rust extensions: where the executable port is moving

The README now points to a Rust-first executable future.

- `README.md:30` says the Rust port is in progress and intended to become the definitive runtime.
- `rust/README.md:3-20` defines a runnable workspace with crates for `api`, `commands`, `compat-harness`, `runtime`, `rusty-claude-cli`, and `tools`.

### Rust CLI/runtime wiring is much closer to a real Claude Code replacement
- `rust/crates/rusty-claude-cli/src/main.rs:13-31` imports a live Anthropic API client, command registry, compat harness, runtime types, and tool executor.
- `rust/crates/rusty-claude-cli/src/main.rs:54-79` dispatches real CLI actions: prompt mode, REPL, login/logout, system prompt rendering, manifest dumping, and session resume.
- `rust/crates/rusty-claude-cli/src/main.rs:130-233` parses `--model`, `--output-format`, `--allowedTools`, `prompt`, `--resume`, and REPL/default flows.

### Rust prompt, permissions, MCP, OAuth, and session plumbing are explicit modules
- `rust/crates/runtime/src/lib.rs:1-78` re-exports modules for:
  - prompt building
  - permissions
  - MCP config/client/stdio
  - OAuth
  - remote session state
  - session + usage tracking
  - file operations and bash execution
- `rust/crates/runtime/src/prompt.rs:37-180` builds a real system prompt with:
  - dynamic boundary markers
  - project context
  - instruction-file discovery (`CLAUDE.md`, `CLAUDE.local.md`, `.claude/CLAUDE.md`)
  - git status capture
  - prompt budgeting / truncation
- `rust/crates/runtime/src/permissions.rs:3-87` implements allow/deny/prompt permission policies with per-tool overrides and interactive prompting.

### Rust tools are actual executable tool specs, not just mirrored metadata
- `rust/crates/tools/src/lib.rs:50-220` defines MVP tool schemas for:
  - `bash`
  - `read_file`
  - `write_file`
  - `edit_file`
  - `glob_search`
  - `grep_search`
  - `WebFetch`
  - `WebSearch`
  - `TodoWrite`
  - `Skill`
  - `Agent`
  - `ToolSearch`
  - more beyond the excerpt
- This is materially different from the Python `src/tools.py`, which mostly mirrors archived inventory entries.

### Rust includes an explicit TypeScript-compat extraction harness
- `rust/crates/compat-harness/src/lib.rs:13-47` resolves upstream TS paths for `src/commands.ts`, `src/tools.ts`, and `src/entrypoints/cli.tsx`.
- `rust/crates/compat-harness/src/lib.rs:93-103` extracts command, tool, and bootstrap manifests from the upstream source.
- `rust/crates/compat-harness/src/lib.rs:186-223` reconstructs the upstream bootstrap plan by scanning the TS CLI entrypoint for version/system-prompt/daemon/background/template/environment-runner fast paths.

## 4. Tests and remaining gaps vs Claude Code

### What is tested today
- `tests/test_porting_workspace.py:15-242` verifies:
  - manifest generation
  - summary/parity/commands/tools CLIs
  - route/show/bootstrap flows
  - tool permission filtering
  - session persistence
  - execution registry behavior
  - bootstrap graph and direct-mode shims
- The tests mainly validate the **mirrored Python harness layer**, not a live Claude-compatible agent runtime.

### Concrete remaining gaps
1. **Archive parity is snapshot-based in this checkout**
   - `python3 -m src.main parity-audit` currently reports: `Local archive unavailable; parity audit cannot compare against the original snapshot.`
   - So this worktree proves structural mirroring through checked-in JSON snapshots, not live TS-to-Python diffing.

2. **Many Python subsystems are placeholders rather than executable ports**
   - `src/utils/__init__.py:1-16` is representative: it exposes metadata from a JSON snapshot (`ARCHIVE_NAME`, `MODULE_COUNT`, `SAMPLE_FILES`) and labels itself a placeholder.
   - `src/remote_runtime.py:16-25` and `src/direct_modes.py:16-21` return placeholder status reports instead of implementing real remote/direct-connect behavior.

3. **Python prompt/runtime remains synthetic**
   - `src/query_engine.py:80-104` generates turn summaries from matched inventory items.
   - `src/system_init.py:8-22` reports loaded counts and startup steps, but Python has no live Anthropic SDK client or full prompt builder analogous to Rust.

4. **The repository itself documents incomplete parity**
   - `README.md:151-153` explicitly says the Python tree still has fewer executable runtime slices than the archived TypeScript source.

5. **One unfinished Python task abstraction is observable in this checkout**
   - `src/tasks.py:6-10` expects `PortingTask`, but `src/task.py` does not define it.
   - Evidence: `python3 -c 'import src.tasks'` currently fails with `ImportError: cannot import name 'PortingTask' ... due to a circular import`.

6. **Rust is practical but still not claiming full upstream parity**
   - `rust/README.md:195-196` says `compat-harness` is excluded from the release test run and that the CLI currently focuses on a practical integrated workflow: prompt execution, REPL, session inspection/resume, config discovery, and tool/runtime plumbing.

## Bottom line

The Python port is best understood as a **clean-room structural mirror** of Claude Code's CLI/runtime surface: it preserves file layout, command/tool inventories, startup phases, routing ideas, session persistence, and permission filtering, but mostly as metadata-backed shims and synthetic turn handling.

The more executable reimplementation effort has already moved into `rust/`, where the project now contains a real API client, system-prompt builder, permission policy, MCP plumbing, tool schemas, OAuth flow, session handling, and an upstream-compat extraction harness.
