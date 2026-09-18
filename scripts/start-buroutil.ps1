[CmdletBinding()]
param(
    [switch]$NoBrowser,
    [switch]$BuildIfMissing,
    [int]$SitePort = 5173,
    [int]$AgentPort = 15721
)
$ErrorActionPreference='Stop'
$Root=Split-Path -Parent $PSScriptRoot
$Site=Join-Path $Root 'site'
$Exe=Join-Path $Root 'artifacts\win-x64\WinUtil.Agent.exe'
$PidDir=Join-Path $env:TEMP 'BuroUtil'
New-Item -ItemType Directory -Path $PidDir -Force | Out-Null

function Test-PortFree([int]$Port) {
  $l=[Net.Sockets.TcpListener]::new([Net.IPAddress]::Loopback,$Port)
  try{$l.Start();return $true}catch{return $false}finally{$l.Stop()}
}

if(-not (Test-Path $Exe)) {
  if(-not $BuildIfMissing){throw "WinUtil.Agent.exe not found. Run .\build.ps1 or start with -BuildIfMissing."}
  if(-not (Get-Command dotnet -ErrorAction SilentlyContinue)){throw ".NET 10 SDK is required for a source build."}
  & (Join-Path $Root 'build.ps1')
  if($LASTEXITCODE -ne 0 -or -not(Test-Path $Exe)){throw 'Build failed.'}
}
if(Test-PortFree $AgentPort){
  $p=Start-Process $Exe -ArgumentList '--background' -WorkingDirectory $Root -WindowStyle Hidden -PassThru
  $p.Id | Set-Content (Join-Path $PidDir 'agent.pid')
}else{Write-Host "Agent port $AgentPort is already in use; using the existing agent." -ForegroundColor Yellow}

if(-not(Test-PortFree $SitePort)){throw "Static site port $SitePort is already in use."}
$p=Start-Process powershell.exe -ArgumentList @('-NoLogo','-NoProfile','-ExecutionPolicy','Bypass','-File',(Join-Path $PSScriptRoot 'serve-static.ps1'),'-Root',$Site,'-Port',$SitePort) -WindowStyle Hidden -PassThru
$p.Id | Set-Content (Join-Path $PidDir 'site.pid')
Start-Sleep -Milliseconds 600
$uri="http://127.0.0.1:$SitePort/"
Write-Host "BuroUtil: $uri" -ForegroundColor Green
if(-not $NoBrowser){Start-Process $uri}
