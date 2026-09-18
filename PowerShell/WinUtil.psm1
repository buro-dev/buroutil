$root = $PSScriptRoot
. "$root\Core.ps1"
. "$root\Registry.ps1"
. "$root\Backup.ps1"
. "$root\Restore.ps1"
. "$root\Operations.ps1"
. "$root\WindowsUpdate.ps1"
. "$root\Providers.ps1"
. "$root\Engine.ps1"
. "$root\Scheduler.ps1"

Export-ModuleMember -Function @(
  'Test-WinUtilAdministrator',
  'Get-WinUtilOSInfo',
  'Get-WinUtilManifest',
  'Get-WinUtilTweakState',
  'Get-WinUtilApplyPlan',
  'Get-WinUtilProvider',
  'Get-WinUtilProviderCatalog',
  'Register-WinUtilProvider',
  'Get-WinUtilAuditTail',
  'Write-WinUtilAudit',
  'Invoke-WinUtilScan',
  'Invoke-WinUtilApply',
  'Invoke-WinUtilRollback',
  'New-WinUtilRestorePoint',
  'Register-WinUtilAgentTask',
  'Register-WinUtilSystemStartupTask',
  'Unregister-WinUtilTasks'
)
