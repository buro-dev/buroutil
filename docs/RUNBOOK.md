# Operational runbook

## First install

1. Build self-contained agent.
2. Run `scripts/install.ps1 -SiteOrigin <exact-origin>` elevated.
3. Copy `site/` to a static host.
4. Open the site.
5. Enter `WinUtil.Agent.exe --show-token` once.
6. Run Scan before Apply.

## Safe workflow

```text
Connect -> Scan -> Select -> Preview -> Apply -> Verify -> Review transaction
```

## Rollback workflow

Use Restore Center. Only reversible transaction items are restored. For system-level OS changes, Windows System Restore remains the broader fallback when it exists.

## If the agent is not reachable

The static site enters demo mode. Demo mode never performs mutations and does not guess current Windows state.

## If the token is lost or suspected compromised

Run:

```powershell
WinUtil.Agent.exe --rotate-token
```

Then reconnect from the static site with the newly printed token.

## If a Windows update changes behavior

Run a fresh Scan. Tweak definitions should be updated with the tested Windows build range before enabling new policies.
