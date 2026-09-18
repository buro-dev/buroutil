# Static site deployment

## 1. Build

```powershell
.\build.ps1
```

## 2. Publish `site/`

Copy `artifacts/site/` to your static provider.

Examples:

- GitHub Pages: publish the contents of `artifacts/site/` from the Pages artifact.
- Cloudflare Pages: set the output directory to `site` (or use the copied artifacts/site contents).
- IIS: create a static website and point it at the `site` directory.

No Node.js build step is required.

## 3. Configure origin

The installed agent must contain the exact static-site origin:

```json
{
  "Agent": {
    "AllowedOrigins": ["https://example.example"]
  }
}
```

The installer can do this for you:

```powershell
.\scripts\install.ps1 -SiteOrigin "https://example.example"
```

## 4. Connect

Open the static site, click **Agent'e Bağlan** and enter:

```powershell
C:\Program Files\WinUtilNG\WinUtil.Agent.exe --show-token
```

The token is stored locally in the browser profile after connection.

## 5. Development

```powershell
python -m http.server 5173 --directory .\site
```

and use:

```text
http://localhost:5173
```

with the default agent CORS entry.
