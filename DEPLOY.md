# BuroUtil deployment

BuroUtil separates the static web UI from the privileged Windows agent.

## Windows end user

A prepared self-contained Windows release can be extracted and launched with `START-BUROUTIL.cmd`.

When using the GitHub source ZIP, the launcher automatically builds the agent when `artifacts\win-x64\WinUtil.Agent.exe` is missing. That source-build path requires the .NET 10 SDK.

The launcher starts the UI on `127.0.0.1:5173`, starts the agent on `127.0.0.1:15721`, and opens the browser.

Stop:

```powershell
.\scripts\stop-buroutil.ps1
```

## Windows install / autostart

Run elevated PowerShell:

```powershell
Set-ExecutionPolicy -Scope Process Bypass
.\scripts\install.ps1 -SiteOrigin "https://YOUR-STATIC-SITE.example"
```

Use an exact HTTPS origin. Do not use a wildcard CORS origin.

## Windows static server

No Node.js is required:

```powershell
.\scripts\serve-static.ps1 -Root .\site -Port 8080
```

Node development server:

```powershell
npm start
```

## Linux / static hosting

Linux should host only the static UI. The privileged Windows Agent and its Windows PowerShell providers run on the user's Windows machine.

Local Linux static server:

```bash
./scripts/serve-linux-static.sh
```

Or:

```bash
python3 -m http.server 8080 --directory site --bind 0.0.0.0
```

Production: use Nginx/Caddy/another HTTPS static server.

A hosted static page can call a loopback agent on the user's own Windows machine when the agent security policy allows the exact site origin.

## Free static hosting

GitHub Pages, Cloudflare Pages, Netlify and ordinary static hosting can serve `site/`. A static host cannot run the privileged Windows Agent.

## Prerequisites

Prepared self-contained Windows releases need no .NET runtime.

Developers using the repository source need:

- .NET 10 SDK
- Windows PowerShell 5.1 on Windows
- Git
- Node.js 20+ only for optional site tooling

Do not silently install software from third-party mirrors.
