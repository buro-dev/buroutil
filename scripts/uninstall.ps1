[CmdletBinding()]
param([string]$InstallRoot = "$env:ProgramFiles\WinUtilNG")

$ErrorActionPreference = 'Stop'
$identity = [Security.Principal.WindowsIdentity]::GetCurrent()
$principal = [Security.Principal.WindowsPrincipal]::new($identity)
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) { throw 'Run uninstaller elevated.' }

foreach ($name in @('WinUtil NG Agent', 'WinUtil NG System Maintenance')) {
    Unregister-ScheduledTask -TaskName $name -Confirm:$false -ErrorAction SilentlyContinue
}
Remove-Item -LiteralPath $InstallRoot -Recurse -Force -ErrorAction SilentlyContinue
Write-Host 'WinUtil NG binaries and scheduled tasks removed.' -ForegroundColor Green
Write-Host 'ProgramData\WinUtil was preserved for logs/backups.'
