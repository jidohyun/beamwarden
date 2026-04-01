# Beamwarden Rename Plan

Date: 2026-04-01
Status: proposed
Owner: leader synthesis from OMX team review

> Update: the actual OTP app rename to `:beamwarden` has now landed, while the module namespace remains `ClawCode.*`. The remaining major rename step is the module/file namespace migration.

## Goal

Rename the project from `claw-code` / `Claw Code` to **Beamwarden** while separating:

1. **branding rename** (repo/docs/public identity)
2. **CLI surface rename**
3. **Elixir application name rename**
4. **Elixir module namespace rename**
5. **environment variable / daemon node default rename**

The key requirement is to avoid breaking the currently working Elixir daemon-first runtime while still giving the project a clean Beamwarden-facing identity.

---

## Current naming surface inventory

### A. Branding / public-facing surfaces

These should be renamed first because they are low-risk and user-visible:

- root `README.md`
- `elixir/README.md`
- docs under `docs/`
- repo slug / GitHub metadata
- release notes / changelog / badges / screenshots / docs titles

Current examples:
- `README.md` title and body text
- `elixir/README.md` title
- docs that still mention `claw-code`, `Claw Code`, or repo history

### B. Compatibility-sensitive CLI surfaces

These are visible to users but affect commands, automation, tutorials, and scripts:

- Mix task command: `mix claw ...`
- daemon examples: `mix claw daemon-run`
- docs showing `mix claw ...`
- any shell aliases or wrappers derived from `claw`

Risk: medium
- changing this breaks docs, scripts, and muscle memory immediately
- best handled with additive aliases before removal

### C. Elixir application identity

These are runtime-coupled and must be migrated carefully:

- Mix app name: `:claw_code` in `elixir/mix.exs`
- application boot: `Application.ensure_all_started(:claw_code)`
- `Application.get_env(:claw_code, ...)`
- any app-name-bound OTP lookup or runtime config

Risk: high
- changing app name affects boot, config, test startup, peer-node startup, and env reads
- this is the first truly breaking runtime rename layer

### D. Elixir module namespace

These are the most invasive code-level rename surfaces:

- `ClawCode.*` modules
- file paths under `elixir/lib/claw_code/`
- references across tests, docs, runtime, and peer-node RPC

Risk: very high
- broad code churn
- high merge-conflict surface
- easy to accidentally break RPC/module lookup and tests

### E. Environment variables and node naming

These are externally visible operational interfaces:

- `CLAW_DAEMON_NODE`
- `CLAW_DAEMON_COOKIE`
- `CLAW_DAEMON_NAME_MODE`
- daemon node default `claw_code_daemon`
- client node prefix `claw_code_cli`

Risk: medium-high
- cross-host docs and operator workflows will break if changed without compatibility aliases

### F. Test and fixture naming

These are lower risk than runtime names but still broad:

- test module names like `ClawCodeDaemonModeTest`
- file names like `claw_code_cluster_test.exs`
- Python test strings / reference subtree naming
- Rust reference naming mentions

Risk: medium
- breaking only if coupled to reflection / doctest / file discovery assumptions

### G. Reference subtree naming

These are not primary runtime surfaces but affect documentation consistency:

- `reference/python/`
- `reference/rust/`
- historical docs referring to older project names

Risk: low-medium
- mostly docs and historical compatibility concern

---

## Recommended rename policy

### Policy recommendation

**Do not rename everything at once.**

Adopt a split policy:

- **Public/project/product name** → `Beamwarden`
- **Internal runtime namespace** → remain `claw_code` until a later compatibility-managed migration

This creates a safe intermediate state:

- repo and docs say **Beamwarden**
- runtime internals still boot reliably
- CLI/app/module rename can happen in staged compatibility phases

This is the safest path because the project already has a working daemon-first runtime and regression suite that should not be destabilized by a cosmetic rename.

---

## Recommended phased migration order

## Phase 0 — Branding-only rename (safe, immediate)

### Scope
- repo title / README / docs / descriptions
- public-facing references from `claw-code` to `Beamwarden`
- keep internal runtime names unchanged

### Deliverables
- root README says Beamwarden
- Elixir README says Beamwarden
- docs use Beamwarden as the project name
- docs explicitly explain that internal runtime namespace still uses `claw_code` temporarily

### Compatibility impact
- none to runtime
- no code breakage expected

### Status
- mostly in progress / partially done already

---

## Phase 1 — Introduce CLI alias without removing `mix claw`

### Goal
Add a new user-facing CLI alias while preserving all current scripts and docs.

### Recommended target
- keep `mix claw` working
- add `mix beamwarden` (or `mix beam`) as the new preferred entrypoint

### Changes
- add a new Mix task file, e.g. `elixir/lib/mix/tasks/beamwarden.ex`
- have it delegate to the same CLI implementation
- update docs to prefer `mix beamwarden ...`
- leave `mix claw ...` documented as compatibility mode for one or more releases

### Compatibility impact
- low
- additive only

### Exit criteria
- both command names pass the same smoke tests
- docs show Beamwarden-first usage

---

## Phase 2 — Rename env vars and daemon node defaults with compatibility fallbacks

### Goal
Move operator-facing env/config names toward Beamwarden without breaking existing setups.

### Recommended target additions
- `BEAMWARDEN_DAEMON_NODE`
- `BEAMWARDEN_DAEMON_COOKIE`
- `BEAMWARDEN_DAEMON_NAME_MODE`
- daemon node default `beamwarden_daemon`
- client node prefix `beamwarden_cli`

### Compatibility rule
For at least one migration phase:
- read new names first
- fall back to old `CLAW_*` names
- warn in docs that old names are deprecated

### Implementation order
1. support both env var families
2. support both daemon node defaults where feasible
3. update docs/examples/tests to prefer `BEAMWARDEN_*`
4. only remove `CLAW_*` after a deliberate breaking release

### Compatibility impact
- medium
- docs + scripts + cross-host runtime guidance affected

---

## Phase 3 — Rename Elixir application identity with dual-boot compatibility strategy

### Goal
Move from app name `:claw_code` to a Beamwarden-native app identity.

### Recommended target
- `:beamwarden`

### Warning
This is the first major runtime-breaking phase.

### Needed preparation
Before doing this phase:
- ensure CLI aliasing is already stable
- ensure env var compatibility layer exists
- ensure tests cover peer-node startup, daemon startup, app env reads, and runtime recovery

### Migration strategy
Recommended conservative approach:
1. rename the Mix app to `:beamwarden`
2. keep a compatibility shim layer where practical for app env reads
3. replace `Application.get_env(:claw_code, ...)` with a shared config helper that checks both app namespaces during migration
4. update peer-node boot/test code to start the new app
5. audit docs, scripts, and tests for app-name assumptions

### Groundwork already safe to land before the actual app rename
- centralize app startup/env access behind a helper (currently `ClawCode.AppIdentity`)
- keep the real runtime app on `:claw_code` until a dedicated breaking phase
- let config reads prefer `:beamwarden` and fall back to `:claw_code` during the migration window
- move peer-node tests to the helper first so the later app rename becomes mostly a one-module change

### Compatibility breakpoints
- `Application.ensure_all_started(:claw_code)` callers
- app env reads/writes in runtime and tests
- any peer-node startup logic in tests
- release packaging / tarball naming

### Rollback strategy
- keep config helper supporting old namespace temporarily
- do not combine this phase with module namespace rename

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
Do this only after phases 1–3 are stable.

Suggested execution:
1. mechanical rename in one dedicated branch
2. add temporary compatibility wrappers/aliases only if really needed
3. immediately run full suite including repeated runs and daemon smoke checks
4. do not combine with unrelated cleanups

### Preferred compatibility stance
Avoid long-lived deep module alias layers unless necessary.
If introduced, keep them short-lived and well documented.

---

## Phase 5 — Test/file naming cleanup and historical subtree alignment

### Scope
- rename test module names/files if desired
- update Python/Rust reference docs mentioning old project name
- clean remaining historical strings where they are user-facing

### Risk
medium-low

This phase should happen after runtime renames settle, not before.

---

## Safest migration order summary

1. **Phase 0:** branding/docs rename
2. **Phase 1:** add `mix beamwarden` alias
3. **Phase 2:** add `BEAMWARDEN_*` env vars + daemon naming compatibility
4. **Phase 3:** rename app name `:claw_code` → `:beamwarden`
5. **Phase 4:** rename `ClawCode.*` module namespace and file tree
6. **Phase 5:** cleanup tests/reference subtree naming

---

## Compatibility breakpoints to watch carefully

### Breakpoint group 1 — User command surface
- `mix claw ...`
- docs/tutorials/examples
- shell scripts and CI snippets

### Breakpoint group 2 — Runtime config surface
- env vars under `CLAW_*`
- daemon node default names
- client node prefix naming

### Breakpoint group 3 — OTP application boot
- `:claw_code` app startup
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

### New coverage recommended before Phase 3 or 4
- explicit tests proving old/new config lookup compatibility
- explicit tests for both CLI names if dual-command period exists
- explicit tests for old/new env vars if dual-env period exists

---

## Rollback strategy

### Rollback principle
Each phase must be individually reversible.

### Practical rollback rules
- do not combine multiple rename layers into one large commit
- ship one compatibility boundary at a time
- keep old interface working until the new one is verified
- remove compatibility shims only after one stable cycle

### Recommended rollback units
- Commit A: branding/docs only
- Commit B: new CLI alias only
- Commit C: env var compatibility only
- Commit D: app name migration only
- Commit E: module namespace migration only

This keeps rollback clean and observable.

---

## Recommended final naming policy

### Public/product naming
- Project name: **Beamwarden**
- Docs and README: Beamwarden-first
- Preferred future CLI: `mix beamwarden`

### Internal namespace policy
Short term:
- keep `:claw_code`, `ClawCode`, and `mix claw` for compatibility

Medium term:
- support both old and new CLI/env naming

Long term:
- converge on:
  - app: `:beamwarden`
  - modules: `Beamwarden.*`
  - CLI: `mix beamwarden`
  - env vars: `BEAMWARDEN_*`

---

## Recommended next action

**Do not jump directly to app/module namespace rename.**

The safest immediate next implementation step is:

### Next implementation slice
1. finish branding/doc rename fully
2. add `mix beamwarden` as an alias for `mix claw`
3. add `BEAMWARDEN_*` env var compatibility alongside existing `CLAW_*`
4. update docs to prefer Beamwarden names while keeping old names as compatibility mode

That gives the project a Beamwarden identity quickly without destabilizing the current daemon-first runtime.

---

## Decision summary

If the goal is a safe rename, the right strategy is:

- **brand first**
- **alias second**
- **runtime namespace last**

That minimizes breakage and preserves the working Elixir daemon-first system while the project transitions to Beamwarden.
