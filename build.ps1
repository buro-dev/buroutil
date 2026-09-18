[CmdletBinding()]
param([ValidateSet('Debug','Release')][string]$Configuration = 'Release')

$ErrorActionPreference = 'Stop'
$root = $PSScriptRoot
$project = Join-Path $root 'src\WinUtil.Agent\WinUtil.Agent.csproj'
$out = Join-Path $root 'artifacts\win-x64'

if (-not (Get-Command dotnet -ErrorAction SilentlyContinue)) { throw 'dotnet SDK not found. Install .NET 10 SDK.' }

dotnet restore $project
dotnet build $project -c $Configuration
dotnet publish $project -c $Configuration -r win-x64 --self-contained true -o $out

$siteOut = Join-Path $root 'artifacts\site'
Remove-Item $siteOut -Recurse -Force -ErrorAction SilentlyContinue
New-Item $siteOut -ItemType Directory -Force | Out-Null
Copy-Item (Join-Path $root 'site\*') $siteOut -Recurse -Force

Write-Host "Build complete: $out" -ForegroundColor Green
Write-Host "Static site: $siteOut" -ForegroundColor Green
