# Contributing

## Design rules

1. Every mutating tweak must have a stable ID.
2. Every tweak must declare scope, risk, reversibility and OS support.
3. UI code must never be the security boundary. Server/agent validation is authoritative.
4. The PowerShell engine must never accept arbitrary browser-supplied code.
5. High-risk changes are opt-in and must have an explanatory description.
6. Irreversible operations must be visibly marked and excluded from automatic rollback.
7. Changes that depend on a Windows build should document the tested build range.
8. Prefer documented Windows APIs/cmdlets over undocumented Registry folklore.

## Pull request checklist

- Manifest entry added/updated.
- Scan state added.
- Apply path added.
- Verify behavior added.
- Rollback added when the operation is reversible.
- Dry-run behavior considered.
- Failure behavior considered.
- Windows 10/11 VM test performed.
- No blanket Appx/service/defender/update removal.
