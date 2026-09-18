[CmdletBinding()]
param(
    [string]$InstallRoot = "$env:ProgramFiles\WinUtilNG",
    [string]$SiteOrigin = "http://localhost:5173"
)

$ErrorActionPreference = 'Stop'

$identity = [Security.Principal.WindowsIdentity]::GetCurrent()
$principal = [Security.Principal.WindowsPrincipal]::new($identity)
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    throw 'Run this installer from an elevated PowerShell window.'
}

$repoRoot = Split-Path -Parent $PSScriptRoot
$project = Join-Path $repoRoot 'src\WinUtil.Agent\WinUtil.Agent.csproj'
$publish = Join-Path $repoRoot 'artifacts\win-x64'

if (-not (Get-Command dotnet -ErrorAction SilentlyContinue)) {
    throw '.NET 10 SDK is required.'
}

Remove-Item -LiteralPath $publish -Recurse -Force -ErrorAction SilentlyContinue
New-Item -LiteralPath $publish -ItemType Directory -Force | Out-Null

dotnet publish $project -c Release -r win-x64 --self-contained true -o $publish

New-Item -LiteralPath $InstallRoot -ItemType Directory -Force | Out-Null
Copy-Item -Path (Join-Path $publish '*') -Destination $InstallRoot -Recurse -Force

$configPath = Join-Path $InstallRoot 'appsettings.json'
$config = Get-Content -LiteralPath $configPath -Raw | ConvertFrom-Json
$config.Agent.AllowedOrigins = @($SiteOrigin)
$config | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $configPath -Encoding UTF8

$dataRoot = Join-Path $env:ProgramData 'WinUtil'
foreach ($dir in @($dataRoot, "$dataRoot\Logs", "$dataRoot\Backups", "$dataRoot\Transactions", "$dataRoot\Jobs")) {
    New-Item -LiteralPath $dir -ItemType Directory -Force | Out-Null
}

foreach ($dir in @('Logs','Backups','Transactions','Jobs')) {
    $path = Join-Path $dataRoot $dir
    icacls.exe $path /inheritance:r /grant "*S-1-5-32-545:(OI)(CI)(RX)" /grant "*S-1-5-32-544:(OI)(CI)(F)" /grant "*S-1-5-18:(OI)(CI)(F)" | Out-Null
}

$exe = Join-Path $InstallRoot 'WinUtil.Agent.exe'
foreach ($name in @('WinUtil NG Agent', 'WinUtil NG System Maintenance')) {
    Unregister-ScheduledTask -TaskName $name -Confirm:$false -ErrorAction SilentlyContinue
}

$currentUser = [Security.Principal.WindowsIdentity]::GetCurrent().Name
$agentAction = New-ScheduledTaskAction -Execute $exe -Argument '--background'
$agentTrigger = New-ScheduledTaskTrigger -AtLogOn -User $currentUser
$agentSettings = New-ScheduledTaskSettingsSet -Hidden -StartWhenAvailable -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries
$agentPrincipal = New-ScheduledTaskPrincipal -UserId $currentUser -LogonType Interactive -RunLevel Highest
Register-ScheduledTask -TaskName 'WinUtil NG Agent' -Action $agentAction -Trigger $agentTrigger -Settings $agentSettings -Principal $agentPrincipal -Description 'WinUtil NG local browser agent.' -Force | Out-Null

$maintenanceAction = New-ScheduledTaskAction -Execute $exe -Argument '--maintenance'
$maintenanceTrigger = New-ScheduledTaskTrigger -AtStartup -RandomDelay (New-TimeSpan -Minutes 2)
$maintenanceSettings = New-ScheduledTaskSettingsSet -Hidden -StartWhenAvailable -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries
$systemPrincipal = New-ScheduledTaskPrincipal -UserId 'SYSTEM' -LogonType ServiceAccount -RunLevel Highest
Register-ScheduledTask -TaskName 'WinUtil NG System Maintenance' -Action $maintenanceAction -Trigger $maintenanceTrigger -Settings $maintenanceSettings -Principal $systemPrincipal -Description 'WinUtil NG read-only startup health scan.' -Force | Out-Null

Write-Host ''
Write-Host 'WinUtil NG installed.' -ForegroundColor Green
Write-Host "Install root : $InstallRoot"
Write-Host "Site origin  : $SiteOrigin"
Write-Host 'Agent token  :' -ForegroundColor Cyan
& $exe --show-token
Write-Host ''
