#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PORT="${PORT:-8080}"
BIND="${BIND:-0.0.0.0}"
command -v python3 >/dev/null || { echo "Install Python 3 first."; exit 1; }
exec python3 -m http.server "$PORT" --directory "$ROOT/site" --bind "$BIND"
