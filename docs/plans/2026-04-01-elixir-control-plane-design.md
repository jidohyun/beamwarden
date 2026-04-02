# Elixir Control-Plane Design

> Historical archive: this design note was written while an in-tree Rust reference subtree still existed. The Rust subtree has since been removed from Beamwarden; any Rust mentions below describe that earlier comparison target.

## Chosen direction
We are treating Elixir as the repository's durable control-plane language rather than trying to beat Rust on raw execution speed. That means the Elixir workspace should be strongest at supervision, resumability, long-running sessions, workflow/task orchestration, and developer-facing introspection.

## Alternatives considered
1. **Rust-style runtime parity in Elixir** — rejected for this pass because it duplicates Rust's role and inflates scope.
2. **Metadata-only Elixir mirror** — rejected because the repo already has that baseline; the next step should justify Elixir's existence through OTP-native orchestration value.
3. **Delete Python/Rust immediately** — rejected because they remain useful as reference/execution companions.

## Recommended implementation slices
- Elixir mirror completeness: close the gap with the Python mirror surface.
- OTP control plane: supervised sessions, task/workflow coordinator, state reporting.
- CLI uplift: expose the new orchestration primitives through the Beamwarden CLI (`mix beamwarden`). Earlier references to the legacy alias belong only in archived migration notes.
- Tests/docs: make the Elixir-first story explicit and verifiable.
