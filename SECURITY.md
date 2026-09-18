# Security model

## Threat model

WinUtil NG assumes the static website may be public. The browser therefore never receives a general-purpose command endpoint.

The local agent:

1. Binds to loopback only (`127.0.0.1`).
2. Requires an installation-specific random token.
3. Validates the request Origin against an exact allow-list.
4. Accepts only known tweak IDs from `Tweaks.json`.
5. Applies profile/risk checks on the server side.
6. Does not accept arbitrary PowerShell text from the browser.
7. Writes PowerShell requests to temporary JSON files instead of interpolating shell commands from the browser.
8. Keeps irreversible actions explicitly marked as such.

## Browser security

The site must be served over HTTPS in production. Configure the exact production origin in `appsettings.json` (the installer accepts `-SiteOrigin`). Do not use `*` for production CORS.

Do not expose the agent on `0.0.0.0`, a LAN IP, or a public DNS name.

## Token

The token is a local capability credential. Treat it as sensitive enough to prevent accidental sharing. If the token is compromised, rotate/delete `C:\ProgramData\WinUtil\agent.token` and restart the agent; a future release will expose formal token rotation from the UI.

## PowerShell

The worker uses the Windows PowerShell 5.1 host supplied by Windows 10/11 for compatibility. It runs with:

```text
-NoLogo -NoProfile -NonInteractive -ExecutionPolicy RemoteSigned
```

The project intentionally does not use `irm ... | iex` or remote execution.

## Dangerous operations

High-risk changes should remain opt-in. The manifest is the policy boundary; the browser cannot create a new provider or execute arbitrary shell text.

## Appx

Appx removal is treated as irreversible in this baseline. Only a small explicit whitelist is included. Microsoft documents `Remove-AppxPackage -AllUsers` as an administrative operation and warns that removal is not automatically reversible; Store app removal is not supported.

## Reporting

Do not put passwords, license keys, API tokens or private user data into issue reports. Include the WinUtil transaction ID, sanitized logs and exact Windows build when reporting failures.
