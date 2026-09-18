# Provider framework (v0.2)

Everything the engine can do to a machine lives behind one contract. Adding a tweak
is a JSON edit; adding a *capability* is one registration block. Neither requires a
change to `Engine.ps1`, to the C# agent, or to the web UI.

## The contract

| Member | Required | Meaning |
| --- | --- | --- |
| `Detect($Tweak)` | yes | Read-only. Returns `Status` = `AlreadyApplied` / `ChangeRequired` / `Ready` / `ReadOnly` / `Unsupported`. |
| `Apply($Tweak,$Tx)` | unless `ReadOnly` | Writes the undo record into the transaction **before** mutating, then mutates. |
| `Verify($Tweak)` | no | Defaults to `Detect`. |
| `Rollback($Item)` | no | Its absence is what makes a provider non-reversible. |

`Kind` is one of:

- **State** — idempotent and verifiable (`Registry`, `ServiceStartup`, `PowerPlan`, `AppxWhitelist`).
  After `Apply` the engine re-runs `Detect`; anything other than `AlreadyApplied` is a
  `VerificationFailed` and the whole transaction rolls back.
- **Action** — one-shot, no persistent desired state (`Cleanup`, `NetworkFlushDns`, `SFC`, `DISM`).
  Not verified, because there is nothing to compare against.
- **ReadOnly** — never mutates (`DefenderStatus`, `FirewallStatus`, `ServiceInventory`,
  `WindowsUpdateStatus`). `Apply` on one of these degrades to a read.

## Adding a tweak

Append an object to `Config/Tweaks.json`, then run `node tools/validate-manifest.mjs`.
No code changes.

## Adding a provider

Add one block to `PowerShell/Providers.ps1`:

```powershell
Register-WinUtilProvider -Name 'ScheduledTaskState' -Kind State `
    -Description 'Enables or disables a scheduled task.' `
    -Detect   { param($Tweak) Test-WinUtilScheduledTask -Tweak $Tweak } `
    -Apply    { param($Tweak, $Transaction) Apply-WinUtilScheduledTask -Tweak $Tweak -Transaction $Transaction } `
    -Rollback { param($Item) Undo-WinUtilScheduledTaskItem -Item $Item }
```

Omitting `-Rollback` is a deliberate declaration that the action cannot be undone.
The validator and the engine both enforce it: a manifest entry with
`"Reversible": true` on a provider with no `Rollback` block fails CI, and
`Invoke-WinUtilTweakApply` throws rather than promising an undo it cannot deliver.

## Safety rules the framework enforces

1. No arbitrary command can enter from the browser — only manifest ids.
2. A `State` change that does not verify aborts and rolls the transaction back.
3. `Reversible` is a claim the provider has to back with code.
4. Profile denials are reported, not silently dropped.
5. Every apply and rollback appends a line to `%ProgramData%\WinUtil\Logs\audit.jsonl`.
