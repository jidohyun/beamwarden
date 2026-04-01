# Rewriting Project Claw Code

<p align="center">
  <strong>⭐ The fastest repo in history to surpass 50K stars, reaching the milestone in just 2 hours after publication ⭐</strong>
</p>

<p align="center">
  <a href="https://star-history.com/#instructkr/claw-code&Date">
    <picture>
      <source media="(prefers-color-scheme: dark)" srcset="https://api.star-history.com/svg?repos=instructkr/claw-code&type=Date&theme=dark" />
      <source media="(prefers-color-scheme: light)" srcset="https://api.star-history.com/svg?repos=instructkr/claw-code&type=Date" />
      <img alt="Star History Chart" src="https://api.star-history.com/svg?repos=instructkr/claw-code&type=Date" width="600" />
    </picture>
  </a>
</p>

<p align="center">
  <img src="assets/clawd-hero.jpeg" alt="Claw" width="300" />
</p>

<p align="center">
  <strong>Better Harness Tools, not merely storing the archive of leaked Claude Code</strong>
</p>

<p align="center">
  <a href="https://github.com/sponsors/instructkr"><img src="https://img.shields.io/badge/Sponsor-%E2%9D%A4-pink?logo=github&style=for-the-badge" alt="Sponsor on GitHub" /></a>
</p>

> [!IMPORTANT]
> **Elixir is now the primary workspace** for this repository. The active developer-facing surface lives under `elixir/` with Mix/OTP-native session and workflow orchestration, while Python and Rust live under `reference/python/` and `reference/rust/` as companion/reference subtrees.

> If you find this work useful, consider [sponsoring @instructkr on GitHub](https://github.com/sponsors/instructkr) to support continued open-source harness engineering research.

---

## Backstory

At 4 AM on March 31, 2026, I woke up to my phone blowing up with notifications. The Claude Code source had been exposed, and the entire dev community was in a frenzy. My girlfriend in Korea was genuinely worried I might face legal action from Anthropic just for having the code on my machine — so I did what any engineer would do under pressure: I sat down, ported the core features to Python from scratch, and pushed it before the sun came up.

The whole thing was orchestrated end-to-end using [oh-my-codex (OmX)](https://github.com/Yeachan-Heo/oh-my-codex) by [@bellman_ych](https://x.com/bellman_ych) — a workflow layer built on top of OpenAI's Codex ([@OpenAIDevs](https://x.com/OpenAIDevs)). I used `$team` mode for parallel code review and `$ralph` mode for persistent execution loops with architect-level verification. The entire porting session — from reading the original harness structure to producing a working Python tree with tests — was driven through OmX orchestration.

That first clean-room Python rewrite established the mirror strategy. This README now reflects the next step: an **Elixir structural mirror** that ports the same harness concepts into a Mix/BEAM workspace while keeping the scope intentionally conservative. The Elixir layer preserves CLI shape, inventories, setup/bootstrap summaries, routing, session persistence, and parity reporting without claiming full Claude Code runtime equivalence. I'm now actively collaborating with [@bellman_ych](https://x.com/bellman_ych) — the creator of OmX himself — to push this further. **Stay tuned — a much more capable version is on the way.**

https://github.com/instructkr/claw-code

![Tweet screenshot](assets/tweet-screenshot.png)

## The Creators Featured in Wall Street Journal For Avid Claude Code Fans

I've been deeply interested in **harness engineering** — studying how agent systems wire tools, orchestrate tasks, and manage runtime context. This isn't a sudden thing. The Wall Street Journal featured my work earlier this month, documenting how I've been one of the most active power users exploring these systems:

> AI startup worker Sigrid Jin, who attended the Seoul dinner, single-handedly used 25 billion of Claude Code tokens last year. At the time, usage limits were looser, allowing early enthusiasts to reach tens of billions of tokens at a very low cost.
>
> Despite his countless hours with Claude Code, Jin isn't faithful to any one AI lab. The tools available have different strengths and weaknesses, he said. Codex is better at reasoning, while Claude Code generates cleaner, more shareable code.
>
> Jin flew to San Francisco in February for Claude Code's first birthday party, where attendees waited in line to compare notes with Cherny. The crowd included a practicing cardiologist from Belgium who had built an app to help patients navigate care, and a California lawyer who made a tool for automating building permit approvals using Claude Code.
>
> "It was basically like a sharing party," Jin said. "There were lawyers, there were doctors, there were dentists. They did not have software engineering backgrounds."
>
> — *The Wall Street Journal*, March 21, 2026, [*"The Trillion Dollar Race to Automate Our Entire Lives"*](https://lnkd.in/gs9td3qd)

![WSJ Feature](assets/wsj-feature.png)

---

## Porting Status

The repository is now best understood as an **Elixir-first clean-room port repository** with Python and Rust companion reference subtrees.

- `elixir/` contains the active Mix/OTP workspace, the primary `mix claw` surface, and the Elixir-owned mirrored reference data under `elixir/priv/reference_data/`
- `reference/python/` contains the earlier Python structural mirror for historical reference/comparison
- `reference/rust/` contains the Rust runtime/reference subtree for deeper runtime comparison
- the exposed snapshot is no longer part of the tracked repository state

The Elixir workspace is intentionally conservative but now materially richer than a pure metadata mirror: it preserves CLI shape, inventories, setup/bootstrap flows, routing, session persistence, parity evidence, and **OTP-native control-plane supervision for sessions and workflows**. It is still **not** runtime-equivalent to Claude Code.

Today the shipped BEAM layer covers both the structural mirror and a lightweight OTP-native control-plane slice: supervised session workers, persisted session snapshots, workflow/task coordination, and CLI commands that expose those primitives. This is still not a full Claude Code runtime, but it is now more than a metadata-only mirror.

The active Elixir workspace now vendors the checked-in snapshot/reference data it executes against under `elixir/priv/reference_data/`, so the Python and Rust trees are retained as reference companions rather than dependencies of the main developer workflow.

## How the Claude Code port maps into the Elixir tree

This repository currently mirrors **architecture, inventory, and control-flow shape** more than it mirrors every runtime behavior. The Elixir port follows the same clean-room strategy that the Python port established, but packages it as a Mix/BEAM workspace and owns the checked-in reference data it needs.

### 1. CLI and runtime architecture mapping

- **CLI entrypoint:** `elixir/lib/mix/tasks/claw.ex` exposes the public Mix task surface, and `elixir/lib/claw_code/cli.ex` handles summary, manifest, parity-audit, bootstrap, routing, turn-loop, control-plane, workflow, session, mode-placeholder, and shim execution commands.
- **Runtime orchestration:** `elixir/lib/claw_code/runtime.ex` is the main Claude-Code-style control-flow mirror. It routes prompts across mirrored command/tool inventories, builds a runtime session, records setup/history, emits stream-style events, and persists sessions.
- **Query/session loop:** `elixir/lib/claw_code/query_engine.ex` models the per-turn engine. It tracks a session id, mutable transcript, permission denials, token-budget accounting, max-turn stopping, structured output, and session persistence.
- **Startup/bootstrap:** `elixir/lib/claw_code/setup.ex`, `elixir/lib/claw_code/prefetch.ex`, `elixir/lib/claw_code/deferred_init.ex`, `elixir/lib/claw_code/system_init.ex`, and `elixir/lib/claw_code/bootstrap_graph.ex` mirror the original startup story: prefetches first, then trust-gated deferred init, then command/tool loading, then the query loop.
- **Mode branching:** `elixir/lib/claw_code/remote_runtime.ex` and `elixir/lib/claw_code/direct_modes.ex` provide Elixir placeholders for remote / SSH / teleport / direct-connect / deep-link branching.
- **OTP control plane:** `elixir/lib/claw_code/control_plane.ex` adds supervised `GenServer` / `DynamicSupervisor` / `Registry` orchestration for resumable sessions plus persisted workflow/task tracking.

### 2. Command, tool, permissions, and control-flow porting

- **Command surface:** `elixir/lib/claw_code/commands.ex` loads the Elixir-owned snapshot copy in `elixir/priv/reference_data/commands_snapshot.json` and exposes lookup, filtering, and shim execution helpers. This remains an inventory mirror of the archived command graph, not a full Elixir reimplementation of every command.
- **Tool surface:** `elixir/lib/claw_code/tools.ex` does the same for `elixir/priv/reference_data/tools_snapshot.json`, including simple-mode filtering, MCP exclusion switches, and permission-context filtering.
- **Execution registry:** `elixir/lib/claw_code/execution_registry.ex` wraps those mirrored command/tool entries so the runtime can “execute” them as descriptive shims during bootstrap and route simulations.
- **Permissions model:** `elixir/lib/claw_code/permissions.ex` implements deny-name / deny-prefix filtering over mirrored tool metadata.
- **Prompt handling:** `elixir/lib/claw_code/runtime.ex` tokenizes a prompt, scores it against mirrored command/tool metadata, then hands the selected entries to `elixir/lib/claw_code/query_engine.ex`, which records the turn and emits a Claude-Code-style result object.
- **Session persistence:** `elixir/lib/claw_code/transcript.ex` and `elixir/lib/claw_code/session_store.ex` keep the replay/flush/persist pieces separate, preserving the broad “stateful agent session” shape.

### 3. Tests and remaining gaps versus Claude Code

- **The Elixir test suite is a smoke-test layer, not full parity validation.** `elixir/test/claw_code_port_test.exs` checks manifest generation, CLI commands, routing/bootstrap flows, permission filtering, session persistence, OTP control-plane session/workflow commands, exit-code behavior, and placeholder mode/report wiring. It does **not** prove that the Elixir tree can replace Claude Code end-to-end.
- **Parity audit is inventory-oriented.** `elixir/lib/claw_code/parity_audit.ex` compares Elixir filenames and directory names against shared archive reference data. On a checkout without the local private archive, `mix claw parity-audit` correctly reports that direct comparison is unavailable.
- **Rust still carries the deeper executable runtime direction.** The Elixir port now owns the primary control-plane/documentation surface, while `reference/rust/` remains the stronger runtime for prompt building, permissions, MCP plumbing, OAuth, and low-level executable tools.

If you want the shortest honest summary: **the repository is now Elixir-first for docs, verification, structural mirror work, and lightweight OTP control-plane behavior — but not yet the full executable depth of Claude Code.**

## Why this rewrite exists

I originally studied the exposed codebase to understand its harness, tool wiring, and agent workflow. After spending more time with the legal and ethical questions—and after reading the essay linked below—I did not want the exposed snapshot itself to remain the main tracked source tree.

This repository now focuses on clean-room porting work instead, with the Elixir mirror presented as the primary developer-facing workspace in this README.

## Repository Layout

```text
.
├── elixir/                             # Elixir structural mirror (Mix project + ExUnit)
│   ├── lib/claw_code
│   └── test
├── reference/
│   ├── python/                         # Historical Python mirror subtree
│   │   ├── src
│   │   ├── tests
│   │   └── docs
│   └── rust/                           # Rust runtime/reference subtree
├── assets/omx/                         # OmX workflow screenshots
├── 2026-03-09-is-legal-the-same-as-legitimate-ai-reimplementation-and-the-erosion-of-copyleft.md
└── README.md
```

## Elixir Primary Workspace Quickstart

The Elixir port lives under `elixir/` and is the primary workspace for this repository. It currently includes:

- a Mix CLI task (`mix claw ...`) for summary, manifest, parity-audit, routing, bootstrap, turn-loop, session, workflow, and mode-placeholder commands
- snapshot-backed command/tool inventories copied into `elixir/priv/reference_data/*.json`
- OTP-native control-plane supervision for resumable sessions and persisted workflows/tasks
- parity evidence against the archived root-file/directory surface plus the shared command/tool snapshots
- supervised session/workflow primitives backed by OTP + persisted snapshot files
- ExUnit coverage for manifest generation, CLI execution, routing/bootstrap/session/workflow behavior, permissions filtering, and mirrored registry execution

Run the Elixir verification flow:

```bash
cd elixir
mix format --check-formatted
mix compile
mix test
```

Try the Elixir CLI surface:

```bash
cd elixir
mix claw summary
mix claw manifest
mix claw setup-report
mix claw bootstrap "review MCP tool"
mix claw daemon-status
mix claw control-plane-status
mix claw start-session --id smoke-session "review MCP tool"
mix claw submit-session smoke-session "review MCP tool"
```

For a short architectural note on the daemon-first OTP supervision layer, see `docs/elixir-control-plane-overview.md`.

Inspect mirrored command/tool inventories:

```bash
cd elixir
mix claw commands --limit 10
mix claw tools --limit 10
mix claw command-graph
mix claw tool-pool
```

Read the current review/design notes:

```text
- docs/elixir-first-review.md
- docs/plans/2026-04-01-elixir-control-plane-design.md
```

## Python Companion Reference Subtree

The original clean-room Python mirror now lives under `reference/python/`. It remains useful as:

- the first-pass port that established the mirror strategy
- a reference implementation for manifest / parity / routing concepts
- a smaller historical comparison target for the Elixir workspace

Elixir now owns its checked-in snapshot fixtures under `elixir/priv/reference_data/`, so the Python subtree is a comparison/reference workspace rather than an input required for `mix compile` or `mix test`.

Elixir now owns its checked-in snapshot fixtures under `elixir/priv/reference_data/`, so the Python subtree is a comparison/reference workspace rather than an input required for `mix compile` or `mix test`.

You can still inspect it with:

```bash
cd reference/python
python3 -m src.main summary
python3 -m src.main manifest
python3 -m src.main parity-audit
python3 -m unittest discover -s tests -v
```

## Current Parity Checkpoint

The port now mirrors the archived root-entry file surface, top-level subsystem names, command/tool inventories, and selected control-plane concepts much more closely than before. However, neither companion port is yet a full runtime-equivalent replacement for the original TypeScript system: the Elixir tree is the primary developer-facing workspace, but it still favors clean-room structural parity and OTP orchestration over full executable upstream parity.


## Built with `oh-my-codex`

The restructuring and documentation work on this repository was AI-assisted and orchestrated with Yeachan Heo's [oh-my-codex (OmX)](https://github.com/Yeachan-Heo/oh-my-codex), layered on top of Codex.

- **`$team` mode:** used for coordinated parallel review and architectural feedback
- **`$ralph` mode:** used for persistent execution, verification, and completion discipline
- **Codex-driven workflow:** used first to establish the Python mirror and then to push the Elixir structural mirror forward

### OmX workflow screenshots

![OmX workflow screenshot 1](assets/omx/omx-readme-review-1.png)

*Ralph/team orchestration view while the README and essay context were being reviewed in terminal panes.*

![OmX workflow screenshot 2](assets/omx/omx-readme-review-2.png)

*Split-pane review and verification flow during the final README wording pass.*

## Community

<p align="center">
  <a href="https://instruct.kr/"><img src="assets/instructkr.png" alt="instructkr" width="400" /></a>
</p>

Join the [**instructkr Discord**](https://instruct.kr/) — the best Korean language model community. Come chat about LLMs, harness engineering, agent workflows, and everything in between.

[![Discord](https://img.shields.io/badge/Join%20Discord-instruct.kr-5865F2?logo=discord&style=for-the-badge)](https://instruct.kr/)

## Star History

See the chart at the top of this README.

## Ownership / Affiliation Disclaimer

- This repository does **not** claim ownership of the original Claude Code source material.
- This repository is **not affiliated with, endorsed by, or maintained by Anthropic**.
