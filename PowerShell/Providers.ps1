Set-StrictMode -Version Latest

# ---------------------------------------------------------------------------
# WinUtil NG - Generic Provider Framework
#
# Every provider is a single object with a common contract:
#
#   Detect($Tweak)                 -> state object  { Id, Status, Current, Desired, Message }
#   Apply($Tweak, $Transaction)    -> result object (records its own undo data in the transaction)
#   Verify($Tweak)                 -> state object  (defaults to Detect)
#   Rollback($TransactionItem)     -> void
#
# Kind:
#   State     idempotent + verifiable (Registry, ServiceStartup, PowerPlan, Appx)
#   Action    one-shot, no persistent desired state (Cleanup, DNS flush, SFC, DISM)
#   ReadOnly  never mutates anything (Defender/Firewall/Service inventory)
#
# Adding a new tweak = one JSON object in Config/Tweaks.json.
# Adding a new capability = one Register-WinUtilProvider call here.
# No C# and no engine changes are required for either.
# ---------------------------------------------------------------------------

$script:WinUtilProviders = @{}

function Register-WinUtilProvider {
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][ValidateSet('State', 'Action', 'ReadOnly')][string]$Kind,
        [Parameter(Mandatory)][scriptblock]$Detect,
        [scriptblock]$Apply,
        [scriptblock]$Verify,
        [scriptblock]$Rollback,
        [string]$Description = ''
    )

    if ($Kind -ne 'ReadOnly' -and -not $Apply) {
        throw "Provider '$Name' is not ReadOnly and therefore requires an Apply block."
    }

    $script:WinUtilProviders[$Name] = [pscustomobject]@{
        Name        = $Name
        Kind        = $Kind
        Description = $Description
        Detect      = $Detect
        Apply       = $Apply
        Verify      = $Verify
        Rollback    = $Rollback
        Reversible  = [bool]$Rollback
    }
}

function Get-WinUtilProvider {
    param([Parameter(Mandatory)][string]$Name)

    if (-not $script:WinUtilProviders.ContainsKey($Name)) {
        throw "Unsupported provider: $Name"
    }

    return $script:WinUtilProviders[$Name]
}

function Get-WinUtilProviderCatalog {
    return @(
        $script:WinUtilProviders.Values |
        Sort-Object Name |
        ForEach-Object {
            [pscustomobject]@{
                Name        = $_.Name
                Kind        = $_.Kind
                Reversible  = $_.Reversible
                Description = $_.Description
            }
        }
    )
}

# --- State providers -------------------------------------------------------

Register-WinUtilProvider -Name 'Registry' -Kind State `
    -Description 'Single registry value with type-preserving write and exact-state rollback.' `
    -Detect   { param($Tweak) Test-WinUtilRegistryTweak -Tweak $Tweak } `
    -Apply    { param($Tweak, $Transaction) Apply-WinUtilRegistryTweak -Tweak $Tweak -Transaction $Transaction } `
    -Rollback { param($Item) Undo-WinUtilRegistryItem -Item $Item }

Register-WinUtilProvider -Name 'ServiceStartup' -Kind State `
    -Description 'Windows service startup mode with previous mode captured for rollback.' `
    -Detect   { param($Tweak) Test-WinUtilServiceTweak -Tweak $Tweak } `
    -Apply    { param($Tweak, $Transaction) Apply-WinUtilServiceTweak -Tweak $Tweak -Transaction $Transaction } `
    -Rollback { param($Item) Undo-WinUtilServiceItem -Item $Item }

Register-WinUtilProvider -Name 'PowerPlan' -Kind State `
    -Description 'Active power scheme; previous active GUID captured for rollback.' `
    -Detect   { param($Tweak) Test-WinUtilPowerPlanTweak -Tweak $Tweak } `
    -Apply    { param($Tweak, $Transaction) Apply-WinUtilPowerPlanTweak -Tweak $Tweak -Transaction $Transaction } `
    -Rollback { param($Item) Undo-WinUtilPowerPlanItem -Item $Item }

# Appx removal is verifiable but NOT reversible: no Rollback block is registered
# on purpose, so the engine can never claim an undo it cannot perform.
Register-WinUtilProvider -Name 'AppxWhitelist' -Kind State `
    -Description 'Removes only the explicit optional-app whitelist. Not reversible.' `
    -Detect { param($Tweak) Test-WinUtilAppxTweak -Tweak $Tweak } `
    -Apply  { param($Tweak, $Transaction) Apply-WinUtilAppxTweak -Tweak $Tweak -Transaction $Transaction }

# --- Action providers ------------------------------------------------------

Register-WinUtilProvider -Name 'Cleanup' -Kind Action `
    -Description 'Deletes unlocked files from the user and Windows TEMP directories.' `
    -Detect { param($Tweak) Test-WinUtilCleanupTweak -Tweak $Tweak } `
    -Apply  { param($Tweak, $Transaction) Apply-WinUtilCleanupTweak -Tweak $Tweak -Transaction $Transaction }

Register-WinUtilProvider -Name 'NetworkFlushDns' -Kind Action `
    -Description 'ipconfig /flushdns' `
    -Detect { param($Tweak) Test-WinUtilNetworkAction -Tweak $Tweak } `
    -Apply  { param($Tweak, $Transaction) Apply-WinUtilNetworkAction -Tweak $Tweak -Transaction $Transaction }

Register-WinUtilProvider -Name 'NetworkWinsockReset' -Kind Action `
    -Description 'netsh winsock reset. May require a reboot.' `
    -Detect { param($Tweak) Test-WinUtilNetworkAction -Tweak $Tweak } `
    -Apply  { param($Tweak, $Transaction) Apply-WinUtilNetworkAction -Tweak $Tweak -Transaction $Transaction }

Register-WinUtilProvider -Name 'DISM' -Kind Action `
    -Description 'dism /Online /Cleanup-Image /RestoreHealth' `
    -Detect { param($Tweak) Test-WinUtilRepairAction -Tweak $Tweak } `
    -Apply  { param($Tweak, $Transaction) Apply-WinUtilRepairAction -Tweak $Tweak -Transaction $Transaction }

Register-WinUtilProvider -Name 'SFC' -Kind Action `
    -Description 'sfc /scannow' `
    -Detect { param($Tweak) Test-WinUtilRepairAction -Tweak $Tweak } `
    -Apply  { param($Tweak, $Transaction) Apply-WinUtilRepairAction -Tweak $Tweak -Transaction $Transaction }

Register-WinUtilProvider -Name 'WindowsUpdateRepair' -Kind Action `
    -Description 'Restarts BITS and wuauserv. Never disables or blocks updates.' `
    -Detect { param($Tweak) Test-WinUtilRepairAction -Tweak $Tweak } `
    -Apply  { param($Tweak, $Transaction) Invoke-WinUtilWindowsUpdateRepair -Tweak $Tweak -Transaction $Transaction }

# --- Read-only providers ---------------------------------------------------

Register-WinUtilProvider -Name 'DefenderStatus' -Kind ReadOnly `
    -Description 'Reads Microsoft Defender status. Never disables protection.' `
    -Detect { param($Tweak) Get-WinUtilDefenderStatus -Tweak $Tweak }

Register-WinUtilProvider -Name 'FirewallStatus' -Kind ReadOnly `
    -Description 'Reads Windows Firewall profile state. Never disables the firewall.' `
    -Detect { param($Tweak) Get-WinUtilFirewallStatus -Tweak $Tweak }

Register-WinUtilProvider -Name 'ServiceInventory' -Kind ReadOnly `
    -Description 'Reads selected service states and startup modes.' `
    -Detect { param($Tweak) Get-WinUtilServiceInventory -Tweak $Tweak }

Register-WinUtilProvider -Name 'WindowsUpdateStatus' -Kind ReadOnly `
    -Description 'Reads Windows Update service state.' `
    -Detect { param($Tweak) Get-WinUtilWindowsUpdateStatus }
