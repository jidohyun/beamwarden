# Beamwarden Rename Plan

Date: 2026-04-01  
Status: archived historical plan  
Owner: leader synthesis from OMX team review

> Historical archive: this document records the staged rename plan as it stood on 2026-04-01. The current operator-facing contract is Beamwarden-only. Any mentions of `mix claw`, `CLAW_*`, `claw_code_daemon`, or `claw_code_cli` below are retained strictly as compatibility-history context, not as supported commands or settings.
>
> Update on 2026-04-02: the OTP app rename to `:beamwarden` has landed. The remaining major rename topic captured here was the module/file namespace migration from `ClawCode.*` to `Beamwarden.*`.

## Goal

This plan captured how to rename the project from `claw-code` / `Claw Code` to **Beamwarden** without destabilizing the daemon-first Elixir runtime while the migration was still in progress.

The work was separated into five layers:

1. branding rename (repo/docs/public identity)
2. CLI surface rename
3. Elixir application name rename
4. Elixir module namespace rename
5. environment-variable / daemon-node-default rename

---

## Historical naming-surface inventory (2026-04-01)

### A. Branding / public-facing surfaces

These were the lowest-risk, highest-visibility rename targets:

- root `README.md`
- `elixir/README.md`
- docs under `docs/`
- repo slug / GitHub metadata
- release notes / changelog / badges / screenshots / docs titles

### B. Legacy CLI compatibility surfaces

At plan time, the repo still had a legacy Mix command name and older tutorials/scripts that depended on it. The migration strategy was to move docs and operators to Beamwarden-first usage before removing the legacy alias in a later breaking cleanup.

### C. Elixir application identity

These were runtime-coupled and required a deliberate migration:

- Mix app name in `elixir/mix.exs`
- application boot via `Application.ensure_all_started/1`
- `Application.get_env/2` and related app-env access
- app-name-bound OTP lookup or runtime config

### D. Elixir module namespace

These were the most invasive code-level rename surfaces:

- `ClawCode.*` modules
- file paths under `elixir/lib/claw_code/`
- references across tests, docs, runtime, and peer-node RPC

### E. Legacy env-var and node-label surfaces

At plan time, older daemon env vars and node-label defaults were still part of the compatibility window. The migration plan treated them as externally visible operator interfaces that needed an explicit deprecation/removal phase rather than an unannounced rename.

### F. Test and fixture naming

These were lower risk than runtime names but still broad:

- test module names and file names tied to the older namespace
- Python test strings / reference subtree naming
- Rust reference naming mentions

### G. Reference subtree naming

These were not primary runtime surfaces but still mattered for documentation consistency:

- `reference/python/`
- `reference/rust/`
- historical docs referring to older project names

---

## Historical policy choice

The 2026-04-01 plan explicitly chose **not** to rename everything at once.

The intended intermediate state was:

- public/project/product name → `Beamwarden`
- runtime internals → migrate in staged compatibility-managed phases

That sequencing minimized breakage while preserving the already-working daemon-first runtime.

---

## Historical phased migration order

## Phase 0 — Branding-only rename

### Scope
- repo title / README / docs / descriptions
- public-facing references from `claw-code` to `Beamwarden`
- no runtime-coupled changes

### Historical status
- mostly completed before this archive update

---

## Phase 1 — CLI compatibility phase

### Historical goal
Introduce a Beamwarden-first Mix entrypoint before removing the older CLI alias.

### Historical exit criteria
- Beamwarden CLI passes the same smoke tests as the older alias
- docs prefer Beamwarden-first usage
- legacy command references are treated as compatibility notes only

### Historical status
- superseded by the 2026-04-02 breaking cleanup that removed the legacy alias from current operator guidance

---

## Phase 2 — Env-var and daemon-label compatibility phase

### Historical goal
Move operator-facing env/config naming toward Beamwarden without breaking existing setups during the transition window.

### Historical implementation order
1. support both naming families during the migration window
2. update docs/examples/tests to prefer Beamwarden naming
3. remove the legacy names only in a deliberate breaking release

### Historical status
- superseded by the 2026-04-02 cleanup that removed the legacy env/node compatibility surface from supported operator docs

---

## Phase 3 — Elixir application identity rename

### Goal
Move from the older app name to the Beamwarden-native app identity.

### Recommended target
- `:beamwarden`

### Historical warning
This was the first major runtime-breaking phase.

### Historical groundwork
- centralize app startup/env access behind a helper
- update peer-node boot/test code to use that helper
- keep the actual app rename isolated from the module/file rename

### Historical status
- landed before this archive update

---

## Phase 4 — Rename module namespace and file tree

### Goal
Rename `ClawCode.*` and `lib/claw_code/` to Beamwarden-native equivalents.

### Recommended target
- `ClawCode.*` → `Beamwarden.*`
- `elixir/lib/claw_code/` → `elixir/lib/beamwarden/`

### Risk level
very high

### Why it is risky
- touches nearly every Elixir source file
- affects RPC targets, tests, docs, and peer-node startup
- likely to create a large, conflict-heavy diff

### Recommended approach
Treat this as a dedicated rename slice:
1. mechanical rename in one dedicated branch
2. add temporary compatibility wrappers only if strictly necessary
3. immediately run the full suite, repeated test runs, and daemon smoke checks
4. do not combine with unrelated cleanups

---

## Phase 5 — Test/file naming cleanup and historical subtree alignment

### Scope
- rename remaining test module names/files where helpful
- update Python/Rust reference docs mentioning old project names
- clean remaining historical strings where they are user-facing

### Historical status
- intended to happen after runtime renames settled

---

## Historical compatibility breakpoints to watch

### Breakpoint group 1 — User command surface
- legacy CLI command references in docs/tutorials/examples
- shell scripts and CI snippets

### Breakpoint group 2 — Runtime config surface
- legacy env-var references
- daemon node default names
- client node prefix naming

### Breakpoint group 3 — OTP application boot
- older app-startup calls
- config namespace reads/writes
- peer-node `Application.ensure_all_started/1`

### Breakpoint group 4 — Module/RPC surface
- `ClawCode.*` references
- remote RPC calls targeting module names
- test helpers that reference modules directly

---

## Required regression coverage before each major phase

### Minimum always-on checks
```bash
cd elixir
mix format --check-formatted
mix compile
mix test

cd reference/python
python3 -m unittest discover -s tests -v
```

### Extra checks required before app/module rename phases
- repeated Elixir test runs (`mix test && mix test`)
- daemon smoke checks
- peer-node startup tests
- daemon-mode session/workflow proxy tests
- failover/recovery regression tests

### Coverage recommended before Phase 3 or 4
- explicit tests proving old/new config lookup compatibility while the migration window was active
- explicit tests for dual-command support while the CLI compatibility window was active
- explicit tests for dual env-var support while the env-var compatibility window was active

---

## Historical rollback strategy

### Rollback principle
Each phase should be individually reversible.

### Practical rollback rules
- do not combine multiple rename layers into one large commit
- ship one compatibility boundary at a time
- verify the new surface before removing the old one
- remove compatibility shims only after a stable cycle

### Recommended rollback units
- Commit A: branding/docs only
- Commit B: Beamwarden CLI alias only
- Commit C: env-var compatibility only
- Commit D: app name migration only
- Commit E: module namespace migration only

---

## Current naming policy

### Current operator-facing naming
- Project name: **Beamwarden**
- Docs and README: Beamwarden-first
- Supported CLI: `mix beamwarden`
- Supported env vars and daemon labels: Beamwarden-prefixed/runtime-native only

### Historical compatibility note
Older `claw_code` / `ClawCode` naming remains relevant only when reading archived plans, reviews, or compatibility-era test fixtures.

---

## Historical decision summary

The safe rename strategy was:

- brand first
- move operators to Beamwarden-first entrypoints and settings
- isolate runtime namespace changes into dedicated breaking phases

That sequencing preserved the working Elixir daemon-first system while the project transitioned to Beamwarden.
