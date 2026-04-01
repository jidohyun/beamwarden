# Beamwarden Phase 4 Rename Review

This note captures the documentation and reviewer concerns for the **module/file namespace** migration from `ClawCode.*` / `elixir/lib/claw_code` to `Beamwarden.*` / `elixir/lib/beamwarden`.

It is meant to travel with the Phase 4 implementation so the code rename and the docs review stay aligned.

## Constraints that should not regress

The Phase 4 rename should preserve the already-landed runtime compatibility surface:

- the OTP app stays `:beamwarden`
- both `mix beamwarden ...` and `mix claw ...` continue to work during this slice
- daemon-first behavior stays intact
- `BEAMWARDEN_*` env vars remain the preferred operator surface
- older `CLAW_*` env vars remain compatibility fallbacks
- existing daemon node labels such as `claw_code_daemon` stay documented until the runtime contract changes in a separate slice

## Code-review hotspots for the namespace move

When the implementation lands, re-check these areas together instead of treating them as isolated renames:

- `elixir/mix.exs`
  - `mod: {ClawCode.Application, []}` must move to the Beamwarden module namespace
- `elixir/lib/mix/tasks/claw.ex`
  - should remain as the compatibility CLI entrypoint
  - runtime dispatch will still need to reach the renamed CLI module
- `elixir/lib/mix/tasks/beamwarden.ex`
  - should remain the preferred CLI entrypoint
  - runtime dispatch should match the renamed CLI module too
- `elixir/lib/claw_code.ex`
  - root helper functions and path helpers must move with the rest of the namespace
- `elixir/lib/claw_code/**/*.ex`
  - alias/import references should be reviewed for missed `ClawCode.*` names after file moves
- `elixir/test/claw_code_*.exs`
  - test module references and file names should be updated together so the suite still reads Beamwarden-first

## Current grep snapshot before the move

A quick repository grep on this pre-Phase-4 branch still shows three broad buckets of old naming:

- source modules and file paths under `elixir/lib/claw_code`
- ExUnit files named `claw_code_*.exs`
- docs that mention `ClawCode.*` as the live implementation namespace

That means a clean Phase 4 finish should update code, tests, and docs in one pass instead of letting the docs lag behind the implementation rename.

## Documentation hotspots to update after the code move

These files currently describe the Beamwarden product correctly, but they still reference the pre-Phase-4 module/file namespace in places that should change with the implementation:

- `README.md`
  - architecture tree still points at `lib/claw_code`
  - implementation guide still names files under `elixir/lib/claw_code/*`
- `docs/elixir-control-plane-overview.md`
  - module bullets still reference `ClawCode.*`
- `docs/elixir-cluster-daemon-review.md`
  - review bullets still reference `ClawCode.*`
- `docs/elixir-daemon-operations.md`
  - one compatibility note still references `ClawCode.CLI.run/1`

## Documentation rewrite rules

Apply these rules when syncing docs with the renamed implementation:

1. Replace `ClawCode.*` with `Beamwarden.*` for live module references.
2. Replace `elixir/lib/claw_code/...` with `elixir/lib/beamwarden/...` for live file-path references.
3. Keep `mix beamwarden ...` as the preferred command surface.
4. Keep `mix claw ...` documented only as a compatibility alias.
5. Do **not** automatically rename daemon node examples like `claw_code_daemon` unless the runtime behavior changes too.
6. Do **not** drop the `CLAW_*` env-var fallback notes until the compatibility path is intentionally removed.

## Suggested post-rename smoke review

After the namespace migration lands, run both the code checks and a quick doc sanity pass:

```bash
cd elixir
mix format --check-formatted
mix compile
mix test
mix test
cd ../reference/python
python3 -m unittest discover -s tests -v
```

Then confirm:

- `rg -n "\\bClawCode\\b|lib/claw_code" README.md docs elixir/test elixir/lib/mix/tasks`
  only shows intentional compatibility references
- docs still describe `mix beamwarden` as preferred and `mix claw` as compatibility mode
- docs that mention the daemon runtime still describe the current daemon-node naming and env-var fallback behavior accurately
