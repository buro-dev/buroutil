Set-StrictMode -Version Latest

function Test-WinUtilRegistryTweak {
    param([Parameter(Mandatory)]$Tweak)
    $settings = $Tweak.Settings
    $state = Get-WinUtilRegistryValueState -Path $settings.RegistryPath -Name $settings.ValueName
    $desired = $settings.DesiredValue
    $desiredKind = [string]$settings.PropertyType
    $applied = $state.Exists -and (([string]$state.Value) -eq ([string]$desired)) -and ($state.Kind -eq $desiredKind)
    return [pscustomobject]@{
        Id = $Tweak.Id
        Status = if ($applied) { 'AlreadyApplied' } else { 'ChangeRequired' }
        Current = $state.Value
        Desired = $desired
        Message = if ($applied) { 'Desired value already present.' } else { 'Registry value differs from desired state.' }
    }
}

function Apply-WinUtilRegistryTweak {
    param(
        [Parameter(Mandatory)]$Tweak,
        [Parameter(Mandatory)]$Transaction
    )
    $s = $Tweak.Settings
    $before = Get-WinUtilRegistryValueState -Path $s.RegistryPath -Name $s.ValueName
    Add-WinUtilTransactionItem -Transaction $Transaction -Item ([pscustomobject]@{
        TweakId = $Tweak.Id
        Provider = 'Registry'
        Reversible = [bool]$Tweak.Reversible
        Data = [pscustomobject]@{ Path = $s.RegistryPath; Name = $s.ValueName; State = $before }
    })
    Set-WinUtilRegistryValue -Path $s.RegistryPath -Name $s.ValueName -Value $s.DesiredValue -PropertyType $s.PropertyType
    return (Test-WinUtilRegistryTweak -Tweak $Tweak)
}

function Undo-WinUtilRegistryItem {
    param([Parameter(Mandatory)]$Item)
    Restore-WinUtilRegistryValueState -Path $Item.Data.Path -Name $Item.Data.Name -State $Item.Data.State
}

function Test-WinUtilPowerPlanTweak {
    param([Parameter(Mandatory)]$Tweak)
    $active = (powercfg /getactivescheme 2>&1 | Out-String).Trim()
    $desired = [string]$Tweak.Settings.Guid
    return [pscustomobject]@{
        Id = $Tweak.Id
        Status = if ($active -match [regex]::Escape($desired)) { 'AlreadyApplied' } else { 'ChangeRequired' }
        Current = $active
        Desired = $desired
        Message = $active
    }
}

function Apply-WinUtilPowerPlanTweak {
    param([Parameter(Mandatory)]$Tweak, [Parameter(Mandatory)]$Transaction)
    $before = (powercfg /getactivescheme 2>&1 | Out-String).Trim()
    Add-WinUtilTransactionItem -Transaction $Transaction -Item ([pscustomobject]@{
        TweakId = $Tweak.Id; Provider = 'PowerPlan'; Reversible = $true;
        Data = [pscustomobject]@{ ActiveBefore = $before }
    })
    & powercfg /setactive $Tweak.Settings.Guid | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "powercfg /setactive failed with code $LASTEXITCODE" }
    return Test-WinUtilPowerPlanTweak -Tweak $Tweak
}

function Undo-WinUtilPowerPlanItem {
    param([Parameter(Mandatory)]$Item)
    $match = [regex]::Match($Item.Data.ActiveBefore, '[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}')
    if ($match.Success) {
        & powercfg /setactive $match.Value | Out-Null
    }
}

function Test-WinUtilCleanupTweak {
    param([Parameter(Mandatory)]$Tweak)
    return [pscustomobject]@{ Id = $Tweak.Id; Status = 'Ready'; Current = $null; Desired = 'Cleanup when applied'; Message = 'Cleanup is an action, not a persistent state.' }
}

function Apply-WinUtilCleanupTweak {
    param([Parameter(Mandatory)]$Tweak, [Parameter(Mandatory)]$Transaction)
    $targets = @($env:TEMP, (Join-Path $env:SystemRoot 'Temp'))
    Add-WinUtilTransactionItem -Transaction $Transaction -Item ([pscustomobject]@{
        TweakId = $Tweak.Id; Provider = 'Cleanup'; Reversible = $false; Data = [pscustomobject]@{ Targets = $targets }
    })
    foreach ($target in $targets) {
        if (-not (Test-Path -LiteralPath $target)) { continue }
        Get-ChildItem -LiteralPath $target -Force -ErrorAction SilentlyContinue | ForEach-Object {
            try { Remove-Item -LiteralPath $_.FullName -Force -Recurse -ErrorAction Stop }
            catch { Write-WinUtilLog -Level DEBUG -Message "Cleanup skipped: $($_.FullName)" }
        }
    }
    return [pscustomobject]@{ Id = $Tweak.Id; Status = 'Applied'; Message = 'Temporary files cleanup attempted.' }
}

function Test-WinUtilNetworkAction {
    param([Parameter(Mandatory)]$Tweak)
    return [pscustomobject]@{ Id = $Tweak.Id; Status = 'Ready'; Message = 'Action available.' }
}

function Apply-WinUtilNetworkAction {
    param([Parameter(Mandatory)]$Tweak, [Parameter(Mandatory)]$Transaction)
    Add-WinUtilTransactionItem -Transaction $Transaction -Item ([pscustomobject]@{
        TweakId = $Tweak.Id; Provider = $Tweak.Provider; Reversible = $false; Data = [pscustomobject]@{}
    })
    switch ($Tweak.Provider) {
        'NetworkFlushDns' {
            & ipconfig.exe /flushdns | Out-Null
            if ($LASTEXITCODE -ne 0) { throw "ipconfig /flushdns failed: $LASTEXITCODE" }
        }
        'NetworkWinsockReset' {
            & netsh.exe winsock reset | Out-Null
            if ($LASTEXITCODE -ne 0) { throw "netsh winsock reset failed: $LASTEXITCODE" }
        }
    }
    return [pscustomobject]@{ Id = $Tweak.Id; Status = 'Applied'; Message = 'Network action completed.' }
}

function Test-WinUtilRepairAction {
    param([Parameter(Mandatory)]$Tweak)
    return [pscustomobject]@{ Id = $Tweak.Id; Status = 'Ready'; Message = 'Repair action available.' }
}

function Apply-WinUtilRepairAction {
    param([Parameter(Mandatory)]$Tweak, [Parameter(Mandatory)]$Transaction)
    Add-WinUtilTransactionItem -Transaction $Transaction -Item ([pscustomobject]@{
        TweakId = $Tweak.Id; Provider = $Tweak.Provider; Reversible = $false; Data = [pscustomobject]@{}
    })
    switch ($Tweak.Provider) {
        'DISM' {
            & dism.exe /Online /Cleanup-Image /RestoreHealth
            if ($LASTEXITCODE -ne 0) { throw "DISM failed with code $LASTEXITCODE" }
        }
        'SFC' {
            & sfc.exe /scannow
            if ($LASTEXITCODE -ne 0) { throw "SFC returned code $LASTEXITCODE" }
        }
    }
    return [pscustomobject]@{ Id = $Tweak.Id; Status = 'Applied'; Message = 'Repair command completed.' }
}

function Get-WinUtilAppxCandidates {
    $allowList = @(
        'Microsoft.BingNews',
        'Microsoft.BingWeather',
        'Microsoft.MicrosoftSolitaireCollection',
        'Microsoft.XboxApp',
        'Microsoft.XboxGamingOverlay',
        'Microsoft.Xbox.TCUI',
        'Microsoft.XboxSpeechToTextOverlay',
        'Microsoft.GetHelp',
        'Microsoft.Getstarted',
        'Microsoft.People',
        'Microsoft.WindowsFeedbackHub'
    )
    $packages = Get-AppxPackage -AllUsers -ErrorAction SilentlyContinue
    return @($packages | Where-Object { $allowList -contains $_.Name })
}

function Test-WinUtilAppxTweak {
    param([Parameter(Mandatory)]$Tweak)
    $count = @(Get-WinUtilAppxCandidates).Count
    return [pscustomobject]@{ Id = $Tweak.Id; Status = if ($count -eq 0) { 'AlreadyApplied' } else { 'ChangeRequired' }; Current = $count; Desired = 0; Message = "$count whitelist package(s) found." }
}

function Apply-WinUtilAppxTweak {
    param([Parameter(Mandatory)]$Tweak, [Parameter(Mandatory)]$Transaction)
    $packages = @(Get-WinUtilAppxCandidates)
    Add-WinUtilTransactionItem -Transaction $Transaction -Item ([pscustomobject]@{
        TweakId = $Tweak.Id; Provider = 'AppxWhitelist'; Reversible = $false;
        Data = [pscustomobject]@{ Packages = @($packages | Select-Object Name, PackageFullName, Version, Architecture) }
    })
    foreach ($pkg in $packages) {
        try {
            Remove-AppxPackage -Package $pkg.PackageFullName -AllUsers -ErrorAction Stop
            Write-WinUtilLog -Level SUCCESS -Message "Removed Appx: $($pkg.PackageFullName)"
        }
        catch {
            Write-WinUtilLog -Level ERROR -Message "Failed Appx: $($pkg.PackageFullName): $($_.Exception.Message)"
        }
    }
    return Test-WinUtilAppxTweak -Tweak $Tweak
}

function Test-WinUtilServiceTweak {
    param([Parameter(Mandatory)]$Tweak)
    $s = Get-CimInstance Win32_Service -Filter "Name='$($Tweak.Settings.ServiceName)'" -ErrorAction SilentlyContinue
    if (-not $s) { return [pscustomobject]@{ Id=$Tweak.Id; Status='Unsupported'; Message='Service not found.' } }
    return [pscustomobject]@{ Id=$Tweak.Id; Status=if ($s.StartMode -ieq $Tweak.Settings.StartupType) { 'AlreadyApplied' } else { 'ChangeRequired' }; Current=$s.StartMode; Desired=$Tweak.Settings.StartupType; Message=$s.DisplayName }
}

function Apply-WinUtilServiceTweak {
    param([Parameter(Mandatory)]$Tweak, [Parameter(Mandatory)]$Transaction)
    $service = Get-CimInstance Win32_Service -Filter "Name='$($Tweak.Settings.ServiceName)'" -ErrorAction Stop
    Add-WinUtilTransactionItem -Transaction $Transaction -Item ([pscustomobject]@{
        TweakId=$Tweak.Id; Provider='ServiceStartup'; Reversible=$true; Data=[pscustomobject]@{ Name=$service.Name; StartMode=$service.StartMode }
    })
    Set-Service -Name $service.Name -StartupType $Tweak.Settings.StartupType -ErrorAction Stop
    return Test-WinUtilServiceTweak -Tweak $Tweak
}

function Undo-WinUtilServiceItem {
    param([Parameter(Mandatory)]$Item)
    $startup = switch ([string]$Item.Data.StartMode) {
        'Auto' { 'Automatic' }
        'Automatic' { 'Automatic' }
        'Manual' { 'Manual' }
        'Disabled' { 'Disabled' }
        default { throw "Unsupported service startup mode: $($Item.Data.StartMode)" }
    }
    Set-Service -Name $Item.Data.Name -StartupType $startup -ErrorAction Stop
}

function Get-WinUtilDefenderStatus {
    param([Parameter(Mandatory=$false)]$Tweak)
    try {
        $s = Get-MpComputerStatus -ErrorAction Stop
        return [pscustomobject]@{
            Id = 'Security.DefenderStatus'
            Status = 'ReadOnly'
            AntivirusEnabled = $s.AntivirusEnabled
            RealTimeProtectionEnabled = $s.RealTimeProtectionEnabled
            AntispywareEnabled = $s.AntispywareEnabled
            TamperProtection = $s.IsTamperProtected
            Message = 'Defender status read without modification.'
        }
    }
    catch {
        return [pscustomobject]@{ Id='Security.DefenderStatus'; Status='Unavailable'; Message=$_.Exception.Message }
    }
}


function Get-WinUtilServiceInventory {
    param([Parameter(Mandatory=$false)]$Tweak)
    $names = @('wuauserv','bits','UsoSvc','DoSvc','Spooler','WinDefend','MpsSvc')
    $items = foreach ($name in $names) {
        $s = Get-CimInstance Win32_Service -Filter "Name='$name'" -ErrorAction SilentlyContinue
        if ($s) { [pscustomobject]@{Name=$s.Name; DisplayName=$s.DisplayName; State=$s.State; StartMode=$s.StartMode} }
    }
    [pscustomobject]@{ Id='Services.Inventory'; Status='ReadOnly'; Data=@($items); Message='Selected service inventory read without modification.' }
}

function Get-WinUtilFirewallStatus {
    param([Parameter(Mandatory=$false)]$Tweak)
    try {
        $profiles = Get-NetFirewallProfile -ErrorAction Stop | Select-Object Name, Enabled, DefaultInboundAction, DefaultOutboundAction
        [pscustomobject]@{ Id='Security.FirewallStatus'; Status='ReadOnly'; Data=@($profiles); Message='Firewall profile state read without modification.' }
    } catch {
        [pscustomobject]@{ Id='Security.FirewallStatus'; Status='Unavailable'; Message=$_.Exception.Message }
    }
}
