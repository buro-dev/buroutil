$ErrorActionPreference='SilentlyContinue'
$d=Join-Path $env:TEMP 'BuroUtil'
foreach($n in 'agent.pid','site.pid'){
  $f=Join-Path $d $n
  if(Test-Path $f){$id=[int](Get-Content $f|Select-Object -First 1);Stop-Process -Id $id -Force;Remove-Item $f -Force}
}
Write-Host 'BuroUtil stopped.' -ForegroundColor Green
