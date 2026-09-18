# Changelog

## 0.2.0

### Added
- **Generic provider framework** (`PowerShell/Providers.ps1`). One registry of
  `Detect / Apply / Verify / Rollback` blocks replaces the three parallel `switch`
  statements in `Engine.ps1`. New capability = one registration; new tweak = JSON only.
- **Real post-apply verification.** v0.1 checked for a `VerificationFailed` status that
  nothing ever produced, so a silently failing write reported success. `State` providers
  are now re-detected after `Apply`, and a mismatch aborts and rolls back the transaction.
- **Dry-run planner** — `Get-WinUtilApplyPlan`, `POST /api/v1/plan`, wired to the UI's
  Preview button. Returns admin/restore-point/reversibility requirements and the tweaks
  the profile refuses, with the reason.
- **Append-only audit trail** at `%ProgramData%\WinUtil\Logs\audit.jsonl`
  (`Write-WinUtilAudit`, `GET /api/v1/audit`): who, when, elevated or not, what changed.
- **Provider catalog endpoint** `GET /api/v1/providers`.
- **Cross-platform manifest validator** `node tools/validate-manifest.mjs`: schema, id
  format, enums, hive/scope/admin coherence, provider existence parsed from
  `Providers.ps1`, and the reversible/rollback contract.
- **Pester contract tests** (`tests/`) including registry apply→verify→rollback
  round-trips under `HKCU:\Software\WinUtilNGTests`.
- **CI** (`.github/workflows/ci.yml`): validator on Linux, `dotnet build` +
  PSScriptAnalyzer + Pester on Windows.
- **Static host** `tools/serve-site.mjs` plus `.replit` for one-command preview.

### Fixed
- **Manifest was never found.** `Core.ps1` resolved `<root>\..\Config\Tweaks.json`,
  which lands outside the repo in development and outside the publish folder after
  `dotnet publish`. Replaced with a candidate probe (`Resolve-WinUtilManifestPath`).
- **Restore points reported false success.** Windows silently skips
  `Checkpoint-Computer` when one was created in the last 24 h
  (`SystemRestorePointCreationFrequency`) or when System Protection is off. The
  restore-point count is now compared before and after, and a skip is reported as a
  failure with the real reason.
- **Rollback reported nothing.** `Invoke-WinUtilRollback` always claimed success even
  when every item failed. It now returns restored / skipped / failed counts.
- **Profile denials were invisible.** Selected tweaks above the profile's risk ceiling
  were dropped without comment; they are now returned as `BlockedByPolicy`.
- `entry.ps1` and `WinUtil.psm1` never dot-sourced `WindowsUpdate.ps1`, so
  `WindowsUpdateStatus` and `WindowsUpdateRepair` threw at runtime.
- Read-only skip in `Invoke-WinUtilApply` was hard-coded to `DefenderStatus`; it now
  covers every `ReadOnly` provider.

### Security
- **DNS-rebinding defence.** The agent now rejects any request whose `Host` header is
  not a loopback value on the configured port, so `evil.example` pointed at 127.0.0.1
  can no longer reach the API.
- **Origin is mandatory for state-changing requests.** `IsOriginAllowed` used to accept
  a missing `Origin` header unconditionally; that is now allowed for `GET` only.

## 0.2.1-hotfix

- Fix ServiceStartup detector parameter binding.
- Preserve profile-blocked selections through server-side apply planning.
- Remove the unused elevated-apply execution path.
- Reject restore-point bypass flags over the browser API.
- Align agent/site version to 0.2.1.
- Tighten ProgramData ACL defaults.
- Store the browser agent token in sessionStorage instead of localStorage.
