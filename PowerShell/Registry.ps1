Set-StrictMode -Version Latest

function Ensure-RegistryKey {
    param([Parameter(Mandatory)][string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) {
        New-Item -Path $Path -Force -ErrorAction Stop | Out-Null
    }
}

function Get-WinUtilRegistryValueState {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$Name
    )

    $exists = Test-Path -LiteralPath $Path
    if (-not $exists) {
        return [pscustomobject]@{ Exists = $false; Value = $null; Kind = $null }
    }

    try {
        $key = Get-Item -LiteralPath $Path -ErrorAction Stop
        $item = $key.GetValue($Name, $null, [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames)
        if ($null -eq $item) {
            $propertyExists = $key.GetValueNames() -contains $Name
            if (-not $propertyExists) {
                return [pscustomobject]@{ Exists = $false; Value = $null; Kind = $null }
            }
        }

        $kind = $key.GetValueKind($Name)
        return [pscustomobject]@{
            Exists = $true
            Value = $item
            Kind = $kind.ToString()
        }
    }
    catch {
        return [pscustomobject]@{ Exists = $false; Value = $null; Kind = $null }
    }
}

function Set-WinUtilRegistryValue {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)]$Value,
        [Parameter(Mandatory)][ValidateSet('String','ExpandString','Binary','DWord','MultiString','QWord')][string]$PropertyType
    )

    Ensure-RegistryKey -Path $Path
    $state = Get-WinUtilRegistryValueState -Path $Path -Name $Name

    if ($state.Exists) {
        $currentKind = $state.Kind
        if ($currentKind -eq $PropertyType) {
            # Set-ItemProperty is intentionally used here for in-place edits.
            Set-ItemProperty -LiteralPath $Path -Name $Name -Value $Value -Force -ErrorAction Stop
        }
        else {
            # Recreate to guarantee the requested RegistryValueKind.
            Remove-ItemProperty -LiteralPath $Path -Name $Name -Force -ErrorAction Stop
            New-ItemProperty -LiteralPath $Path -Name $Name -Value $Value -PropertyType $PropertyType -Force -ErrorAction Stop | Out-Null
        }
    }
    else {
        New-ItemProperty -LiteralPath $Path -Name $Name -Value $Value -PropertyType $PropertyType -Force -ErrorAction Stop | Out-Null
    }
}

function Restore-WinUtilRegistryValueState {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)]$State
    )

    Ensure-RegistryKey -Path $Path

    $current = Get-WinUtilRegistryValueState -Path $Path -Name $Name
    if ($current.Exists) {
        Remove-ItemProperty -LiteralPath $Path -Name $Name -Force -ErrorAction SilentlyContinue
    }

    if ([bool]$State.Exists) {
        $value = $State.Value
        $kind = [string]$State.Kind
        New-ItemProperty -LiteralPath $Path -Name $Name -Value $value -PropertyType $kind -Force -ErrorAction Stop | Out-Null
    }
}
