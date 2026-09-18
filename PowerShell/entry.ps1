[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$RequestFile
)

$root = Split-Path -Parent $PSScriptRoot
. (Join-Path $PSScriptRoot 'Core.ps1')
. (Join-Path $PSScriptRoot 'Registry.ps1')
. (Join-Path $PSScriptRoot 'Backup.ps1')
. (Join-Path $PSScriptRoot 'Restore.ps1')
. (Join-Path $PSScriptRoot 'Operations.ps1')
. (Join-Path $PSScriptRoot 'WindowsUpdate.ps1')
. (Join-Path $PSScriptRoot 'Providers.ps1')
. (Join-Path $PSScriptRoot 'Engine.ps1')
. (Join-Path $PSScriptRoot 'Scheduler.ps1')

function Emit-Result {
    param([Parameter(Mandatory)]$Object)
    $Object | ConvertTo-Json -Depth 30 -Compress
}

try {
    $request = Get-Content -LiteralPath $RequestFile -Raw -Encoding UTF8 | ConvertFrom-Json

    switch ($request.Action) {
        'scan' {
            $tweaks = @(Get-WinUtilTweaksById -Ids @($request.TweakIds))
            $data = Invoke-WinUtilScan -Tweaks $tweaks
            Emit-Result ([pscustomobject]@{ Success=$true; Message='Scan completed.'; Data=$data })
        }
        'preview' {
            $tweaks = @(Get-WinUtilTweaksById -Ids @($request.TweakIds))
            $profile = if ($request.Profile) { [string]$request.Profile } else { 'safe' }
            $allowed = switch ($profile.ToLowerInvariant()) { 'safe' {@('Low')} 'balanced' {@('Low','Medium')} 'aggressive' {@('Low','Medium','High')} default { throw 'Invalid profile.' } }
            $tweaks = @($tweaks | Where-Object { $allowed -contains $_.Risk })
            $data = Invoke-WinUtilScan -Tweaks $tweaks
            Emit-Result ([pscustomobject]@{ Success=$true; Message='Preview completed. No changes were made.'; Data=$data })
        }
        'plan' {
            $plan = Get-WinUtilApplyPlan -Ids @($request.TweakIds) -Profile (
                if ($request.Profile) { [string]$request.Profile } else { 'safe' }
            )
            Emit-Result ([pscustomobject]@{ Success = $true; Message = 'Plan generated. No changes were made.'; Data = $plan })
        }

        'providers' {
            Emit-Result ([pscustomobject]@{ Success = $true; Message = 'Provider catalog.'; Data = @(Get-WinUtilProviderCatalog) })
        }

        'audit' {
            Emit-Result ([pscustomobject]@{ Success = $true; Message = 'Audit tail.'; Data = @(Get-WinUtilAuditTail -Count 200) })
        }

        'apply' {
            $data = Invoke-WinUtilApply -Ids @($request.TweakIds) -TransactionId ([string]$request.TransactionId) -Profile ([string]$request.Profile) -AllowWithoutRestorePoint ([bool]$request.AllowWithoutRestorePoint)
            Emit-Result ([pscustomobject]@{ Success=$data.Success; Message=$data.Message; Data=$data })
        }
        'rollback' {
            $data = Invoke-WinUtilRollback -TransactionId ([string]$request.TransactionId)
            Emit-Result ([pscustomobject]@{ Success=$data.Success; Message=$data.Message; Data=$data })
        }
        'maintenance' {
            $os = Get-WinUtilOSInfo
            Write-WinUtilLog -Level INFO -Message "System startup maintenance scan: $($os.Caption) build $($os.Build)"
            $manifest = Get-WinUtilManifest
            $enabled = @($manifest.Tweaks | Where-Object { $_.EnabledByDefault -eq $true -and $_.Scope -eq 'System' })
            $data = Invoke-WinUtilScan -Tweaks $enabled
            Emit-Result ([pscustomobject]@{ Success=$true; Message='Startup maintenance scan completed. No settings changed.'; Data=$data })
        }
        'install-tasks' {
            $exe = Join-Path $root 'WinUtil.Agent.exe'
            Register-WinUtilAgentTask -ExecutablePath $exe
            Register-WinUtilSystemStartupTask -ExecutablePath $exe
            Emit-Result ([pscustomobject]@{ Success=$true; Message='Scheduled tasks installed.' })
        }
        'remove-tasks' {
            Unregister-WinUtilTasks
            Emit-Result ([pscustomobject]@{ Success=$true; Message='Scheduled tasks removed.' })
        }
        default {
            throw "Unknown action: $($request.Action)"
        }
    }
}
catch {
    try { Write-WinUtilLog -Level ERROR -Message $_.Exception.Message } catch { }
    Emit-Result ([pscustomobject]@{ Success=$false; Message=$_.Exception.Message })
    exit 1
}
