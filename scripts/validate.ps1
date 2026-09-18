[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot

Write-Host 'Validating WinUtil NG manifest...' -ForegroundColor Cyan
$manifestPath = Join-Path $root 'Config\Tweaks.json'
$manifest = Get-Content $manifestPath -Raw -Encoding UTF8 | ConvertFrom-Json

if ($manifest.SchemaVersion -ne 1) { throw 'Unsupported manifest schema.' }
$ids = @($manifest.Tweaks | ForEach-Object Id)
$dupes = $ids | Group-Object | Where-Object Count -gt 1
if ($dupes) { throw "Duplicate tweak IDs: $($dupes.Name -join ', ')" }

foreach ($t in $manifest.Tweaks) {
    foreach ($property in @('Id','Name','Category','Provider','Risk','Scope')) {
        if ([string]::IsNullOrWhiteSpace([string]$t.$property)) { throw "Missing $property in $($t.Id)" }
    }
    if ($t.Risk -notin @('Low','Medium','High')) { throw "Invalid risk in $($t.Id)" }
    if ($t.Scope -notin @('User','System')) { throw "Invalid scope in $($t.Id)" }
}

$requiredFiles = @(
    'site\index.html',
    'site\styles.css',
    'site\app.js',
    'site\config.js',
    'src\WinUtil.Agent\Program.cs',
    'src\WinUtil.Agent\WinUtil.Agent.csproj',
    'PowerShell\entry.ps1',
    'PowerShell\Engine.ps1'
)

foreach ($relative in $requiredFiles) {
    if (-not (Test-Path (Join-Path $root $relative))) { throw "Missing: $relative" }
}

Write-Host "Validated $($ids.Count) tweak(s)." -ForegroundColor Green
Write-Host 'Validation complete.' -ForegroundColor Green
