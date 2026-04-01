# Elixir-first Reference Reduction Design

## Chosen direction
We keep Python and Rust in-tree, but make them clearly secondary by removing Elixir's direct dependency on Python-owned snapshot files and by rewriting reference docs to sound archival/reference-oriented rather than active-primary.

## Implementation slices
- Vendor snapshot data into Elixir-owned paths.
- Rewrite documentation references from `src/` and `rust/` to `reference/python/` and `reference/rust/` where appropriate.
- Keep Python tests runnable from the subtree so the historical mirror remains verifiable.
