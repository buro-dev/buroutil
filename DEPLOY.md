# BuroUtil deployment

BuroUtil separates the static web UI from the privileged Windows agent.

## Windows end user

Extract the release ZIP and double-click `START-BUROUTIL.cmd`.

For a source checkout, build first with:

```powershell
Set-ExecutionPolicy -Scope Process Bypass
.\build.ps1
```

Then:

```powershell
.\scripts\start-buroutil.ps1
```

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

## Linux

Linux can host the static UI. Windows-specific PowerShell providers require Windows.

Simple static test:

```bash
python3 -m http.server 8080 --directory site --bind 0.0.0.0
```

Production: use Nginx/Caddy/another HTTPS static server.

The Windows Agent should not be exposed from a Linux server. A hosted static page can call a loopback agent on the user's own Windows machine when the browser and agent security policy allow the exact origin.

## Free static hosting

GitHub Pages, Cloudflare Pages, Netlify and basic static hosting can serve `site/`. InfinityFree-style hosting can also serve ordinary static HTML/CSS/JS if the host permits it.

Important: static hosting cannot run the privileged Windows Agent. The user's Windows PC still needs the local agent.

## Prerequisites

End users should receive a self-contained Windows release so no .NET runtime is required.

Developers need:

- .NET 10 SDK for source builds
- Windows PowerShell 5.1 on Windows
- Git
- Node.js 20+ only for optional site tooling

Do not silently install software from third-party mirrors.
