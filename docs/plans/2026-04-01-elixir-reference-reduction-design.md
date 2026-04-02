# Elixir-first Reference Reduction Design

> Historical archive: this plan predates the Rust subtree removal. References to Python and Rust below describe the earlier in-tree comparison setup, not the current repository layout.

## Chosen direction
At the time of this plan, we kept Python and Rust in-tree, but aimed to make them clearly secondary by removing Elixir's direct dependency on Python-owned snapshot files and by rewriting reference docs to sound archival/reference-oriented rather than active-primary.

## Implementation slices
- Vendor snapshot data into Elixir-owned paths.
- Rewrite documentation references from `src/` and `rust/` to `reference/python/` and the then-existing `reference/rust/` where appropriate.
- Keep Python tests runnable from the subtree so the historical mirror remains verifiable.
