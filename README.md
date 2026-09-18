# WinUtil NG

**WinUtil NG** is an original, open-source Windows maintenance architecture inspired by the *ideas* behind tools such as Chris Titus Tech WinUtil and O&O ShutUp10: a curated set of Windows operations, a reversible transaction layer, and a privacy-focused control surface.

It is intentionally not a browser-only "registry editor". The public/static portion is a zero-dependency HTML/CSS/JS application. A local .NET 10 agent performs Windows operations only on `127.0.0.1` and requires a per-installation token plus a strict CORS origin allow-list.

## What is new in 0.2

The engine no longer dispatches with `switch` statements. Every capability is a
provider registered in `PowerShell/Providers.ps1` behind one contract:

```text
Detect -> Backup -> Apply -> Verify -> Rollback
```

Practical consequences:

- **A new tweak is a JSON edit.** No C#, no engine change. `node tools/validate-manifest.mjs`
  gates it in CI.
- **Verification is real.** v0.1 looked for a `VerificationFailed` status that nothing
  produced, so a write that silently failed still reported success. `State` providers are
  re-detected after apply, and a mismatch rolls the whole transaction back.
- **`Reversible` has to be earned.** A provider without a `Rollback` block cannot carry a
  tweak marked reversible - the validator fails CI and the engine throws.
- **Dry run before anything happens.** `POST /api/v1/plan` (the UI's Preview button)
  reports the admin, restore-point and reversibility requirements, plus every tweak the
  profile refuses and why.
- **Append-only audit trail** at `%ProgramData%\WinUtil\Logs\audit.jsonl`: who, when,
  elevated or not, what changed, what rolled back.

See `docs/PROVIDERS.md` for the contract and `docs/CHANGELOG.md` for the fixes,
including the manifest path bug that prevented v0.1 from loading `Tweaks.json` at all.

## Quick start without Windows

```bash
npm start                          # serves site/ on :5000 in demo mode
node tools/validate-manifest.mjs   # manifest contract check
```

Demo mode renders the whole UI, including the planner, and cannot touch a machine:
no agent on `127.0.0.1:15721` means no PowerShell, no registry, no Appx.


## Why the architecture is different

A normal static web page cannot safely or directly change the Windows Registry, services, scheduled tasks, Appx packages or system repair state. WinUtil NG therefore separates:

```text
Static Site (deploy anywhere)
        |
        | HTTPS/HTTP to loopback only
        v
WinUtil.Agent.exe (.NET 10)
        |
        +--> Auth + Origin validation
        +--> Manifest validation
        +--> Job manager
        +--> PowerShell worker
        |
        v
Windows 10/11 APIs + PowerShell
```

The agent is normally started for the interactive administrator user at logon with `Highest` privileges. The separate `SYSTEM` startup task performs a **read-only health scan** and never starts the web API as SYSTEM.

## Technology baseline

The project targets `.NET 10`, which is the active LTS release as of September 2026. PowerShell 7.6 is also the current LTS line, but the shipped worker intentionally uses Windows PowerShell 5.1 for Windows-client compatibility because it is an OS component on Windows 10/11. A future release can switch the worker to `pwsh` when present. Microsoft lists .NET 10 as LTS through November 14, 2028 and PowerShell 7.6 as LTS through November 2028. 

## Project tree

```text
WinUtil-NG/
├─ src/WinUtil.Agent/          # .NET 10 local agent
├─ PowerShell/                 # Windows operation modules
├─ Config/Tweaks.json          # manifest: IDs, risk, scope, provider
├─ site/                       # deployable static web UI
├─ scripts/install.ps1         # machine installation + tasks
├─ scripts/uninstall.ps1
├─ build.ps1
└─ docs/
```

## Build

On a Windows development machine with the .NET 10 SDK:

```powershell
Set-ExecutionPolicy -Scope Process Bypass
.\build.ps1
```

The expected publish output is:

```text
artifacts/win-x64/
  WinUtil.Agent.exe
  PowerShell/
  Config/
```

and the static site is copied to:

```text
artifacts/site/
```

For a self-contained win-x64 deployment:

```powershell
dotnet publish .\src\WinUtil.Agent\WinUtil.Agent.csproj `
  -c Release `  -r win-x64 `
  --self-contained true `
  -o .\artifacts\win-x64
```

## Install the local agent

Run elevated PowerShell:

```powershell
.\scripts\install.ps1 -SiteOrigin "https://YOUR-STATIC-SITE.example"
```

The installer:

1. Publishes the self-contained agent.
2. Installs it below `C:\Program Files\WinUtilNG`.
3. Creates `C:\ProgramData\WinUtil` for jobs, transactions, logs and backups.
4. Generates an installation token.
5. Locks down the token file ACL.
6. Registers `WinUtil NG Agent` at user logon with `Highest` and `Hidden`.
7. Registers `WinUtil NG System Maintenance` at system startup with `Highest` and `Hidden`; that task only performs a read-only startup health scan.

Microsoft documents `New-ScheduledTaskTrigger -AtLogOn`, `-AtStartup`, `New-ScheduledTaskPrincipal -RunLevel Highest` and `New-ScheduledTaskSettingsSet -Hidden`.

## Static site deployment

The `site/` directory is deliberately framework-free. It can be hosted as static files on GitHub Pages, Cloudflare Pages, Netlify, an internal IIS static site, or another static host.

Set the local agent's allowed origin to the exact URL of the deployed site:

```json
"AllowedOrigins": [
  "https://example.github.io"
]
```

Then open the static site and enter the local token once. The token is stored only in browser `localStorage`.

### Development

The site can be served locally with any static HTTP server, for example:

```powershell
python -m http.server 5173 --directory .\site
```

Then the static site origin is `http://localhost:5173`.

## Profiles

The manifest defines a risk level for every operation:

```text
Safe       = Low
Balanced   = Low + Medium
Aggressive = Low + Medium + High
```

Aggressive is never the default. The profile is enforced server-side, not merely by the UI.

## Safety model

Every mutating operation follows the engine pattern:

```text
Validate IDs
   -> Validate profile
   -> Check OS
   -> Check administrator
   -> Create transaction
   -> Optional Restore Point
   -> Capture reversible state
   -> Apply
   -> Verify
   -> Commit
```

When a reversible operation fails, the engine attempts to roll back reversible transaction items in reverse order. Microsoft documents `Remove-AppxPackage` as a package removal operation and notes that removal is not automatically reversible; Microsoft also notes Store app removal is unsupported. WinUtil NG therefore keeps Appx debloat explicit, whitelist-based and non-reversible rather than pretending it has an automatic undo path.

## Included operations

### Privacy
- Windows telemetry policy value
- legacy Cortana policy value
- legacy per-user Bing Search policy value
- legacy Cortana consent value
- Advertising ID
- Feedback/SIUF frequency
- consumer features policy

Important: privacy policy keys are described as **policy/configuration changes**, not as a guarantee that every Microsoft service or Windows build will stop all telemetry. Some entries are legacy and may have little or no effect on modern builds.

### Cleanup
- User TEMP cleanup
- Windows TEMP cleanup

Files locked by a running process are skipped.

### Performance
- High Performance power plan

The UI warns that laptops can use more power and generate more heat.

### Network
- Flush DNS
- Winsock reset

Winsock reset is marked medium-risk and may require a restart.

### Maintenance
- `DISM /Online /Cleanup-Image /RestoreHealth`
- `sfc /scannow`

### Debloat
- Explicit Appx whitelist only
- Microsoft Store intentionally excluded
- No blanket `Get-AppxPackage | Remove-AppxPackage`

### Services
- Example advanced action: Delivery Optimization (`DoSvc`) -> Manual
- Disabled by default and marked High risk

### Security
- Defender status is **read-only** in this baseline. Security controls are not silently disabled.

## API surface

```text
GET  /api/v1/health
GET  /api/v1/status
GET  /api/v1/tweaks
POST /api/v1/scan
POST /api/v1/preview
POST /api/v1/apply
GET  /api/v1/jobs/{id}
GET  /api/v1/transactions
POST /api/v1/rollback/{transactionId}
```

Protected requests require:

```text
Origin: https://your-static-site.example
X-WinUtil-Token: <installation token>
Content-Type: application/json
```

The agent is bound to `127.0.0.1`; it is not intended to be an internet-facing API.

## What this project deliberately does not do

- Disable Defender or Windows Firewall as an optimization shortcut.
- Turn Windows Update permanently off.
- Disable UAC globally.
- Remove arbitrary Appx packages.
- Apply undocumented "FPS boost" Registry packs blindly.
- Download and execute remote scripts (`irm ... | iex`).
- Run the browser API as SYSTEM.

## Roadmap

### Stage 1 — Engine
- [x] Manifest-driven tweak IDs
- [x] Scan / Preview / Apply
- [x] Transaction records
- [x] Registry state capture
- [x] Verify-after-apply
- [x] Reversible rollback path
- [x] Restore point gate

### Stage 2 — Windows modules
- [x] Privacy
- [x] Cleanup
- [x] Debloat whitelist
- [x] Services
- [x] Power
- [x] Network
- [x] Windows repair
- [x] Read-only Defender status

### Stage 3 — Web UI
- [x] Dashboard
- [x] Categories
- [x] Search
- [x] Risk badges
- [x] Profiles
- [x] Scan / Preview / Apply
- [x] Jobs / progress
- [x] Restore Center
- [x] Demo mode

### Stage 4 — Background
- [x] User logon agent task
- [x] SYSTEM startup read-only maintenance task
- [x] Hidden task settings

### Stage 5 — Hardening / productization
- [ ] Auth token rotation UI
- [ ] Signed manifest verification
- [ ] Code signing certificate + MSIX/MSI
- [ ] Windows Event Log provider
- [ ] ETW/performance metrics
- [ ] Differential backups
- [ ] Pester + integration test suite on Windows 10/11 VMs
- [ ] WinGet source/app inventory
- [ ] Scheduled maintenance profiles
- [ ] Optional service-based privileged broker if multi-user fleet support is required
- [ ] Offline policy bundles

## Inspiration and license

This is an original implementation. It is compatible in concept with public ideas found in Windows maintenance/privacy tooling but does not embed or copy third-party source code. See `LICENSE` and `SECURITY.md`.
