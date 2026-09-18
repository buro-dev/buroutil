# WinUtil NG Static UI

This directory is deployable as-is to a static host.

1. Edit `config.js` only when the agent URL changes.
2. Put the exact public site origin into the agent's `appsettings.json` through `install.ps1 -SiteOrigin`.
3. Do not embed the agent token in this repository.
4. Use an HTTPS static site in production.
5. The site enters demo mode when the agent is unavailable; demo mode never mutates Windows.
