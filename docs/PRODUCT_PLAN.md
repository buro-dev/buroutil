# Product plan

## Phase 0 — bootstrap

- Static web UI that works without a build framework.
- Local agent on `127.0.0.1`.
- Per-installation token.
- Exact CORS origin allow-list.
- Manifest-driven tweak inventory.

## Phase 1 — safe operations

- Privacy policies.
- Temp cleanup.
- Read-only security/update/service inventory.
- Network repair actions.
- Windows component repair.

## Phase 2 — transaction engine

- Pre-state capture.
- Restore point gate.
- Verify-after-apply.
- Reverse-order rollback for reversible providers.
- Explicit irreversible flags.

## Phase 3 — product UX

- Dashboard.
- Search.
- Profiles.
- Risk tags.
- Preview/dry-run.
- Progress/jobs.
- Restore Center.
- Demo mode.

## Phase 4 — deployment

- Self-contained Windows x64 agent.
- Hidden user-logon task with Highest.
- Hidden SYSTEM startup read-only health task.
- Static hosting compatibility.

## Phase 5 — enterprise hardening

- Windows Event Log source.
- Signed manifest bundles.
- Code signing/MSIX/MSI.
- Versioned offline policy packs.
- Multi-user privileged broker.
- Pester + VM matrix for Windows 10/11 builds.
- WinGet integration with explicit source selection.
- Scheduled maintenance policies.
