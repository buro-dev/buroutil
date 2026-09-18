# Architecture

## Layers

```text
+-----------------------------------------------------------+
|                 Static Web Application                   |
|  index.html / styles.css / app.js / demo-tweaks.json     |
+------------------------------+----------------------------+
                               |
                      authenticated HTTP
                               |
                               v
+-----------------------------------------------------------+
|                 WinUtil.Agent (.NET 10)                   |
|                                                           |
|  CORS -> Token -> Manifest -> Job Manager -> PowerShell   |
+------------------------------+----------------------------+
                               |
                               v
+-----------------------------------------------------------+
|                    PowerShell Engine                      |
|                                                           |
| Core | Registry | Restore | Backup | Operations | Tasks   |
+------------------------------+----------------------------+
                               |
              +----------------+-----------------+
              |                |                 |
              v                v                 v
           Registry        Scheduled Tasks   Windows CLI/API
              |                |                 |
              +----------------+-----------------+
                               |
                               v
                        Windows 10/11
```

## Privilege boundary

The browser-facing agent runs in the interactive administrator user's context. This is deliberate because `HKCU` must represent the active user's hive. A separate SYSTEM startup task does not start the browser API; it performs a read-only health scan.

If the product later needs non-admin users to request machine-level changes, introduce a separate privileged broker (Windows service or UAC-launched one-shot helper) rather than granting the web API unconditional SYSTEM access.

## Transaction boundary

Each apply creates:

```text
ProgramData\WinUtil\Transactions\<id>.json
```

Registry/service/power-plan state is captured before mutation. When a reversible operation fails, the engine walks captured reversible items in reverse order.

Irreversible operations remain visible in the transaction record but are skipped by rollback.

## Static hosting

The site has no build-time framework dependency and can be copied byte-for-byte to a static host. The only local dependency is the agent URL, which defaults to `http://127.0.0.1:15721`.

## Why not localhost SYSTEM

A privileged HTTP API that is reachable from a browser and running as SYSTEM creates an unnecessarily large blast radius. The architecture therefore keeps browser access in a per-user elevated session and uses the SYSTEM task only for non-interactive, non-HTTP startup checks.
