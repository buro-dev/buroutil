#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
command -v dotnet >/dev/null || { echo "Install .NET 10 SDK first."; exit 1; }
dotnet publish "$ROOT/src/WinUtil.Agent/WinUtil.Agent.csproj" -c Release -r linux-x64 --self-contained true -o "$ROOT/artifacts/linux-x64"
