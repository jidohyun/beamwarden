# Evidence for Claude Code → Python Port Analysis

This appendix captures the concrete command outputs used to support `docs/claude-code-port-analysis.md`.

Observed in `worker-1` on `2026-04-01` from worktree `./.omx/team/study-this-repository-starting/worktrees/worker-1`.

## Workspace manifest

Command:

```bash
python3 -m src.main manifest
```

Observed result:

- Port root: `src/`
- Total Python files: **66**
- The manifest enumerates mirrored top-level modules including `query_engine.py`, `tools.py`, `runtime.py`, `permissions.py`, `assistant`, `utils`, `remote`, and `services`.

## Bootstrap session over mirrored command/tool inventories

Command:

```bash
python3 -m src.main bootstrap 'review MCP tool' --limit 5
```

Observed result:

- Built-in command names: **141**
- Loaded command entries: **207**
- Loaded tool entries: **184**
- Routed matches:
  - command: `UltrareviewOverageDialog`
  - tools: `ListMcpResourcesTool`, `MCPTool`, `McpAuthTool`, `ReadMcpResourceTool`
- Persisted session path was written under `.port_sessions/`.

## Route command

Command:

```bash
python3 -m src.main route 'review MCP tool' --limit 5
```

Observed result:

```text
command	UltrareviewOverageDialog	1	commands/review/UltrareviewOverageDialog.tsx
tool	ListMcpResourcesTool	2	tools/ListMcpResourcesTool/ListMcpResourcesTool.ts
tool	MCPTool	2	tools/MCPTool/MCPTool.ts
tool	McpAuthTool	2	tools/McpAuthTool/McpAuthTool.ts
tool	ReadMcpResourceTool	2	tools/ReadMcpResourceTool/ReadMcpResourceTool.ts
```

## Permission filtering

Command:

```bash
python3 -m src.main tools --limit 8 --deny-prefix mcp
```

Observed result:

- Tool count drops from **184** to **182**.
- MCP-prefixed tools are filtered out of the rendered list.

## Parity audit in this checkout

Command:

```bash
python3 -m src.main parity-audit
```

Observed result:

```text
# Parity Audit
Local archive unavailable; parity audit cannot compare against the original snapshot.
```

This confirms that the current checkout depends on checked-in reference snapshots rather than a live local upstream archive.

## Observable Python gap: task abstraction

Command:

```bash
python3 -c 'import src.tasks'
```

Observed result:

```text
ImportError cannot import name 'PortingTask' from partially initialized module 'src.task' (most likely due to a circular import)
```

This is a concrete example of the Python workspace still containing incomplete runtime slices.

## Verification commands run for this research task

### Syntax / compile check

```bash
python3 -m compileall src tests
```

Result: PASS

### Python test suite

```bash
python3 -m unittest discover -s tests -v
```

Result: PASS — **22 tests** completed successfully.

### Rust workspace test suite

```bash
cargo test --workspace --exclude compat-harness
```

Result: NOT RUN — `cargo` is not installed in this environment (`zsh:1: command not found: cargo`).
