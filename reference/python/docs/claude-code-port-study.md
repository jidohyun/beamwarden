# Claude Code → Python Port Study

> Historical note: these paths were written when the Python companion lived at the repo root and a Rust reference subtree still existed in-tree. The Python mirror now lives under `reference/python/`. The Rust subtree has since been removed from Beamwarden, so any Rust paths below are archival references only.

This note summarizes the Python companion workspace that remains in the repository for comparison/reference. The active workspace is now `elixir/`.

## 1. CLI and runtime architecture mapping

The README explicitly frames the repository as a clean-room Python rewrite that preserves Claude Code's harness patterns while moving the active implementation surface into `src/` and verification into `tests/` (`README.md:38-42`, `README.md:66-74`, `README.md:82-110`, `README.md:151-153`).

The Python CLI entrypoint is `src/main.py`. It recreates a Claude-Code-like surface by exposing:

- workspace summary / manifest commands,
- command and tool inventory views,
- prompt routing and bootstrap simulation,
- turn-loop execution,
- session save/load,
- remote / ssh / teleport / direct-connect / deep-link modes,
- direct command/tool execution shims.

See `src/main.py:21-91` for the parser shape and `src/main.py:94-208` for command dispatch.

The startup/runtime path is mirrored in a lightweight way:

- `src/bootstrap_graph.py:16-27` encodes the staged startup flow: prefetch, trust gate, setup, deferred init, mode routing, query loop.
- `src/setup.py:12-27` and `src/setup.py:64-77` model workspace setup plus trusted startup side effects.
- `src/runtime.py:89-152` builds a runtime session by collecting context, setup, routed command/tool matches, execution messages, stream events, and a persisted session artifact.
- `src/query_engine.py:61-150` provides the stateful turn loop: max-turn budgeting, transcript storage, permission-denial tracking, and session persistence.

The result is best understood as a *runtime skeleton* rather than a full Claude Code clone: the control-flow shape is mirrored, but many steps are summary-oriented rather than model/API-backed execution.

## 2. SDK, prompts, tools, permissions, and control-flow porting

### Command + tool surface

The Python port does not reimplement 207 commands and 184 tools one-by-one in Python logic. Instead, it mirrors the upstream surface from archived metadata snapshots:

- `src/commands.py:10-45` loads `src/reference_data/commands_snapshot.json` into `PortingModule` entries.
- `src/tools.py:11-41` does the same for `src/reference_data/tools_snapshot.json`.
- `src/commands.py:75-90` and `src/tools.py:81-96` execute as metadata shims ("would handle ...") instead of full behavior.

This makes the Python layer a surface-compatibility inventory and routing workspace, not yet a behaviorally complete command/tool runtime.

### Prompt + turn loop

The Python side ports the turn loop in simplified form:

- `src/query_engine.py:15-43` defines turn config, usage summary, and transcript state.
- `src/query_engine.py:61-104` turns a prompt into a compact summary containing matched commands, matched tools, and permission denials.
- `src/query_engine.py:106-127` emits streaming-style events.
- `src/query_engine.py:171-193` renders a workspace summary from the manifest plus mirrored inventories.

Compared with the Rust runtime prompt system, the Python version is intentionally thinner. The Rust implementation has a real `SystemPromptBuilder`, project-context discovery, instruction-file loading, git-status capture, and config-aware prompt synthesis in `rust/crates/runtime/src/prompt.rs:37-239`.

### Permissions

The Python permission layer is narrow:

- `src/permissions.py:6-20` only models deny-by-name / deny-by-prefix filtering.
- `src/runtime.py:169-174` hardcodes one important runtime behavior: tools with `bash` in the name are denied as "destructive shell execution remains gated in the Python port".

By contrast, the Rust runtime already implements a fuller permission policy:

- `rust/crates/runtime/src/permissions.rs:3-87` supports `Allow`, `Deny`, and `Prompt` modes with per-tool overrides.
- The same file includes tests for tool-specific prompt-based authorization (`rust/crates/runtime/src/permissions.rs:89-117`).

### Control-flow and session persistence

The Python runtime preserves the broad Claude Code control-flow shape:

- route prompt → collect command/tool matches (`src/runtime.py:90-107`)
- bootstrap a session with context/setup/history (`src/runtime.py:109-152`)
- submit a turn and track budget/transcript (`src/query_engine.py:61-150`)
- save and reload sessions (`src/session_store.py:14-31`)

But the executable fidelity is still limited. The Rust runtime already contains:

- session/message structures with `tool_use` / `tool_result` blocks (`rust/crates/runtime/src/session.rs:9-135`, `rust/crates/runtime/src/session.rs:172-214`)
- executable bash tooling with timeout/background support (`rust/crates/runtime/src/bash.rs:10-160`)
- richer runtime composition exported from `rust/crates/runtime/src/lib.rs:1-78`

## 3. Rust extensions, tests, and remaining gaps vs Claude Code

### Rust extensions

The repository README says the Rust port is intended to become the definitive faster, memory-safe runtime (`README.md:30-32`). The Rust workspace is already organized as a practical CLI:

- `rust/README.md:3-20` lays out `api`, `commands`, `compat-harness`, `runtime`, `rusty-claude-cli`, and `tools`.
- `rust/README.md:42-49` defines the release test command.
- `rust/README.md:145-191` documents top-level CLI commands, slash commands, and runtime environment variables.

Most importantly, the Rust runtime already has real MCP/stdin plumbing:

- `rust/crates/runtime/src/mcp_stdio.rs:312-430` defines `McpServerManager` and tool discovery over `tools/list`.
- `rust/crates/runtime/src/mcp_stdio.rs:433-460` calls MCP tools through indexed routes.
- `rust/crates/runtime/src/mcp_stdio.rs:768-803` spawns stdio MCP processes and builds initialize params.

That is a deeper implementation level than the Python snapshot-driven tool shims.

### Tests and verification coverage

The Python test suite verifies the porting workspace as a consistent mirror layer rather than as a full Claude runtime:

- `tests/test_porting_workspace.py:15-25` checks manifest + summary generation.
- `tests/test_porting_workspace.py:27-43` checks CLI `summary` and `parity-audit`.
- `tests/test_porting_workspace.py:45-56` checks parity expectations only when a local ignored archive exists.
- `tests/test_porting_workspace.py:58-76` validates command/tool snapshot scale.
- `tests/test_porting_workspace.py:104-137` validates bootstrap and execution shims.
- `tests/test_porting_workspace.py:176-244` validates permission filtering, turn loop, remote/direct modes, and execution registry behavior.

The parity audit itself makes the repository's current state explicit:

- `src/parity_audit.py:13-70` maps archived TS roots/directories onto Python targets.
- `src/parity_audit.py:84-110` reports direct comparison metrics.
- `src/parity_audit.py:121-138` falls back to reference snapshot counts when the local archive is absent.

### Remaining gaps vs Claude Code

The main gaps are structural and intentional:

1. **Python is still a mirror/simulation layer for much of the surface.**  
   Commands/tools are loaded from snapshots and execute as descriptive shims (`src/commands.py:75-80`, `src/tools.py:81-86`).

2. **Prompt/runtime fidelity is partial.**  
   Python tracks turn state and budget, but does not yet match the richer prompt synthesis and runtime config path visible in the Rust runtime (`src/query_engine.py:61-193` vs. `rust/crates/runtime/src/prompt.rs:37-239`).

3. **Permissions are simplified in Python.**  
   Python only filters names/prefixes plus a hardcoded bash denial, while Rust already supports policy modes and interactive prompting (`src/permissions.py:6-20`, `src/runtime.py:169-174`, `rust/crates/runtime/src/permissions.rs:3-117`).

4. **Remote/direct modes are placeholders on the Python side.**  
   The Python commands return simple status reports, not full remote transport implementations (`src/remote_runtime.py:6-25`, `src/direct_modes.py:6-21`).

5. **Archive parity is evidence-backed but incomplete at runtime level.**  
   README openly says the Python tree is not yet a full runtime-equivalent replacement (`README.md:151-153`), and `python3 -m src.main parity-audit` currently reports that the local archive is unavailable for direct comparison.

## Bottom line

This repository did **not** port Claude Code to Python as a full end-to-end reimplementation of the original runtime. It ported:

- the **surface shape** (CLI commands, tool inventory, subsystem names, bootstrap stages),
- the **session/control-flow skeleton** (turn loop, transcript, session persistence, routing),
- and the **porting evidence layer** (manifest, parity audit, test-backed inventories).

The deeper executable runtime work is now split: a lightweight Python mirror workspace in `src/`, and a more capable, increasingly real runtime in `rust/`, where prompt construction, permissions, session modeling, bash execution, and MCP stdio integration are implemented with much higher fidelity.
