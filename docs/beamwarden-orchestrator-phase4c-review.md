# Beamwarden Orchestrator Phase 4C Review Focus

Review the Phase 4C implementation for these constraints:
- `task-list` must expose explicit recovery reasons, not just timestamps or implied states.
- Scope must remain task-list-only; no drive-by expansion into `run-status`, cleanup, raw tailing, or TUI.
- Healthy tasks should remain compact and not gain noisy recovery metadata.
- Reason vocabulary should stay deterministic and documented.
