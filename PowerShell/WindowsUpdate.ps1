Set-StrictMode -Version Latest

function Get-WinUtilWindowsUpdateStatus {
    $names = @('wuauserv','bits','UsoSvc')
    $items = foreach ($name in $names) {
        $s = Get-Service -Name $name -ErrorAction SilentlyContinue
        if ($s) {
            [pscustomobject]@{ Name=$s.Name; Status=$s.Status.ToString(); StartType=$s.StartType.ToString() }
        }
    }
    return [pscustomobject]@{
        Id = 'WindowsUpdate.Status'
        Status = 'ReadOnly'
        Services = @($items)
        Message = 'Windows Update service status read without modification.'
    }
}

function Invoke-WinUtilWindowsUpdateRepair {
    param([Parameter(Mandatory)]$Tweak, [Parameter(Mandatory)]$Transaction)
    Add-WinUtilTransactionItem -Transaction $Transaction -Item ([pscustomobject]@{ TweakId=$Tweak.Id; Provider=$Tweak.Provider; Reversible=$false; Data=[pscustomobject]@{} })
    foreach ($name in @('bits','wuauserv')) {
        try {
            Restart-Service -Name $name -Force -ErrorAction Stop
            Write-WinUtilLog -Level SUCCESS -Message "Windows Update service restarted: $name"
        } catch {
            Write-WinUtilLog -Level WARN -Message "Windows Update service restart skipped: $name"
        }
    }
    return [pscustomobject]@{ Id=$Tweak.Id; Status='Applied'; Message='BITS and Windows Update services were restarted where possible.' }
}
