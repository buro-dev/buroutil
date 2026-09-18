# BuroUtil

Windows bakım, gizlilik, tanılama ve güvenli optimizasyon aracı.

## Quick start

Windows kullanıcıları kaynak ZIP'i açtıktan sonra `START-BUROUTIL.cmd` dosyasına çift tıklayabilir. Bu launcher yerel statik UI'yi ve loopback-only Windows Agent'ı başlatır ve tarayıcıyı açar.

Geliştirici kurulumu için `DEPLOY.md` ve `docs/` belgelerine bakın.

## Security boundary

The web UI is untrusted presentation code. Privileged operations are validated by the local agent. The agent must remain bound to loopback and must use an exact allowed-origin list.

## Repository layout

- `PowerShell/` provider engine
- `src/WinUtil.Agent/` local Windows agent
- `Config/Tweaks.json` tweak manifest
- `site/` static UI
- `scripts/` launch/install/deployment helpers
- `tests/` PowerShell tests
- `docs/` architecture and deployment documentation

## Support

Windows-specific privileged providers require Windows. Linux hosting can serve the static UI but is not a remote Windows administration backend.
