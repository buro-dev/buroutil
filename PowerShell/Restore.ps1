Set-StrictMode -Version Latest

function New-WinUtilRestorePoint {
    param([string]$Description = 'WinUtil NG - Before Changes')

    if (-not (Test-WinUtilAdministrator)) {
        return [pscustomobject]@{ Success = $false; Message = 'Administrator privileges required.' }
    }

    if (-not (Get-Command Checkpoint-Computer -ErrorAction SilentlyContinue)) {
        return [pscustomobject]@{ Success = $false; Message = 'Checkpoint-Computer is unavailable on this system.' }
    }

    # Windows silently ignores Checkpoint-Computer if a restore point was created in
    # the last 24h (SystemRestorePointCreationFrequency) or if System Protection is
    # off. v0.1 reported success in both cases. Capture the sequence number first and
    # confirm a NEW point actually appeared.
    $before = $null
    try { $before = @(Get-ComputerRestorePoint -ErrorAction Stop) } catch { }

    if ($null -ne $before -and $before.Count -eq 0) {
        Write-WinUtilLog -Level WARN -Message 'No existing restore points found; System Protection may be disabled.'
    }

    try {
        Checkpoint-Computer -Description $Description -RestorePointType MODIFY_SETTINGS -ErrorAction Stop

        $after = $null
        try { $after = @(Get-ComputerRestorePoint -ErrorAction Stop) } catch { }

        if ($null -ne $before -and $null -ne $after -and $after.Count -le $before.Count) {
            Write-WinUtilLog -Level WARN -Message 'Checkpoint-Computer returned without creating a restore point.'
            return [pscustomobject]@{
                Success = $false
                Throttled = $true
                Message = 'Windows did not create a restore point. This usually means System Protection is disabled for the system drive, or one was already created within the last 24 hours (SystemRestorePointCreationFrequency).'
            }
        }
        Write-WinUtilLog -Level SUCCESS -Message "Restore point created: $Description"
        return [pscustomobject]@{ Success = $true; Message = 'Restore point created.' }
    }
    catch {
        Write-WinUtilLog -Level WARN -Message "Restore point failed: $($_.Exception.Message)"
        return [pscustomobject]@{ Success = $false; Message = $_.Exception.Message }
    }
}
