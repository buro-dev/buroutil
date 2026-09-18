Set-StrictMode -Version Latest

$script:WinUtilRiskProfiles = @{
    safe       = @('Low')
    balanced   = @('Low','Medium')
    aggressive = @('Low','Medium','High')
}

function Get-WinUtilAllowedRisk {
    param([Parameter(Mandatory)][string]$Profile)
    $key = $Profile.ToLowerInvariant()
    if (-not $script:WinUtilRiskProfiles.ContainsKey($key)) { throw 'Profile must be safe, balanced or aggressive.' }
    return $script:WinUtilRiskProfiles[$key]
}

function Get-WinUtilTweakState {
    param([Parameter(Mandatory)]$Tweak)
    $provider = Get-WinUtilProvider -Name $Tweak.Provider
    return & $provider.Detect $Tweak
}

function Invoke-WinUtilTweakApply {
    param([Parameter(Mandatory)]$Tweak, [Parameter(Mandatory)]$Transaction)

    $provider = Get-WinUtilProvider -Name $Tweak.Provider

    if ($provider.Kind -eq 'ReadOnly') { return & $provider.Detect $Tweak }

    if ($Tweak.Reversible -eq $true -and -not $provider.Reversible) {
        throw "Manifest marks $($Tweak.Id) as reversible but provider '$($provider.Name)' has no rollback implementation."
    }

    $result = & $provider.Apply $Tweak $Transaction

    # Real post-apply verification. This step was declared in v0.1 but never
    # executed, so a silently failing write still reported success.
    if ($provider.Kind -eq 'State') {

        $verifier = if ($provider.Verify) { $provider.Verify } else { $provider.Detect }
        $after = & $verifier $Tweak

        if ([string]$after.Status -ne 'AlreadyApplied') {
            Write-WinUtilLog -Level ERROR -Message "Verification failed for $($Tweak.Id): post-apply status is $($after.Status)."
            return [pscustomobject]@{
                Id = $Tweak.Id
                Status = 'VerificationFailed'
                Current = $after.Current
                Desired = $after.Desired
                Message = "The change was written but the system did not report the desired state (post-apply status: $($after.Status))."
            }
        }

        return [pscustomobject]@{
            Id = $Tweak.Id
            Status = 'Applied'
            Current = $after.Current
            Desired = $after.Desired
            Verified = $true
            Message = 'Applied and verified.'
        }
    }

    return $result
}

function Undo-WinUtilTransaction {
    param([Parameter(Mandatory)]$Transaction)

    $items = @($Transaction.Items)
    [array]::Reverse($items)

    $undone = 0; $skipped = 0; $failed = 0

    foreach ($item in $items) {

        if (-not [bool]$item.Reversible) { $skipped++; continue }

        try {
            $provider = Get-WinUtilProvider -Name $item.Provider

            if (-not $provider.Rollback) {
                Write-WinUtilLog -Level WARN -Message "No rollback implementation for provider $($item.Provider); skipping $($item.TweakId)."
                $skipped++
                continue
            }

            & $provider.Rollback $item
            $undone++
            Write-WinUtilLog -Level SUCCESS -Message "Rollback succeeded: $($item.TweakId)"
        }
        catch {
            $failed++
            Write-WinUtilLog -Level ERROR -Message "Rollback failed: $($item.TweakId): $($_.Exception.Message)"
        }
    }

    return [pscustomobject]@{ Undone = $undone; Skipped = $skipped; Failed = $failed }
}

function Get-WinUtilApplyPlan {
    # Dry-run planner. Returns one row per requested tweak, including the ones the
    # profile refuses, so the UI can explain a skip instead of silently dropping it.
    param(
        [Parameter(Mandatory)][string[]]$Ids,
        [string]$Profile = 'safe'
    )

    $allowed = Get-WinUtilAllowedRisk -Profile $Profile
    $isAdmin = Test-WinUtilAdministrator
    $tweaks  = @(Get-WinUtilTweaksById -Ids $Ids)
    $rows    = New-Object System.Collections.Generic.List[object]

    foreach ($t in $tweaks) {

        $blocked = @()
        if ($allowed -notcontains $t.Risk) { $blocked += "Risk '$($t.Risk)' is not permitted by the '$Profile' profile." }
        if ($t.RequiresAdmin -eq $true -and -not $isAdmin) { $blocked += 'Administrator privileges are required.' }

        $state = $null; $stateMessage = $null
        try { $state = Get-WinUtilTweakState -Tweak $t }
        catch { $stateMessage = $_.Exception.Message }

        $rows.Add([pscustomobject]@{
            Id = $t.Id
            Name = $t.Name
            Category = $t.Category
            Provider = $t.Provider
            Risk = $t.Risk
            Reversible = [bool]$t.Reversible
            RequiresAdmin = [bool]$t.RequiresAdmin
            RequiresRestorePoint = [bool]$t.RequiresRestorePoint
            Status = if ($blocked.Count -gt 0) { 'BlockedByPolicy' } elseif ($state) { $state.Status } else { 'Failed' }
            Current = if ($state) { $state.Current } else { $null }
            Desired = if ($state) { $state.Desired } else { $null }
            Blocked = @($blocked)
            Message = if ($blocked.Count -gt 0) { $blocked -join ' ' } elseif ($state) { $state.Message } else { $stateMessage }
        })
    }

    $actionable = @($rows | Where-Object { $_.Status -eq 'ChangeRequired' -or $_.Status -eq 'Ready' })
    return [pscustomobject]@{
        Profile = $Profile
        IsAdministrator = $isAdmin
        RequiresRestorePoint = (@($actionable | Where-Object { $_.RequiresRestorePoint }).Count -gt 0)
        FullyReversible = (@($actionable | Where-Object { -not $_.Reversible }).Count -eq 0)
        TotalRequested = $rows.Count
        ActionableCount = $actionable.Count
        BlockedCount = @($rows | Where-Object { $_.Status -eq 'BlockedByPolicy' }).Count
        Items = @($rows)
    }
}

function Invoke-WinUtilScan {
    param([Parameter(Mandatory)]$Tweaks)
    $results = New-Object System.Collections.Generic.List[object]
    foreach ($t in $Tweaks) {
        try { $results.Add((Get-WinUtilTweakState -Tweak $t)) }
        catch { $results.Add([pscustomobject]@{ Id=$t.Id; Status='Failed'; Message=$_.Exception.Message }) }
    }
    return @($results)
}

function Invoke-WinUtilApply {
    param(
        [Parameter(Mandatory)][string[]]$Ids,
        [string]$TransactionId = ([guid]::NewGuid().ToString('N')),
        [string]$Profile = 'safe',
        [bool]$AllowWithoutRestorePoint = $false
    )

    if (-not (Test-WinUtilSupportedOS)) { throw 'WinUtil NG supports Windows 10 and Windows 11 clients.' }

    $allTweaks = @(Get-WinUtilTweaksById -Ids $Ids)
    $riskAllowed = Get-WinUtilAllowedRisk -Profile $Profile
    $denied = @($allTweaks | Where-Object { $riskAllowed -notcontains $_.Risk })
    $Tweaks = @($allTweaks | Where-Object { $riskAllowed -contains $_.Risk })
    if ($Tweaks.Count -eq 0) { throw 'No selected tweaks are permitted by the chosen profile.' }

    $adminRequired = @($Tweaks | Where-Object { $_.RequiresAdmin -eq $true }).Count -gt 0
    if ($adminRequired -and -not (Test-WinUtilAdministrator)) { throw 'Administrator privileges are required for the selected changes.' }

    Write-WinUtilAudit -Event 'apply.start' -TransactionId $TransactionId -Data ([pscustomobject]@{
        Profile = $Profile; TweakIds = @($Tweaks.Id); Denied = @($denied.Id)
    })

    $transaction = New-WinUtilTransaction -TransactionId $TransactionId -TweakIds ($Tweaks.Id)
    $needsRestorePoint = @($Tweaks | Where-Object { $_.RequiresRestorePoint -eq $true }).Count -gt 0

    if ($needsRestorePoint) {
        $rp = New-WinUtilRestorePoint -Description ("WinUtil NG - {0}" -f $TransactionId)
        $transaction.RestorePoint = $rp.Success
        $transaction.RestorePointMessage = $rp.Message
        Save-WinUtilTransaction -Transaction $transaction
        if (-not $rp.Success -and -not $AllowWithoutRestorePoint) {
            $transaction.Status = 'BlockedNoRestorePoint'
            $transaction.CompletedUtc = (Get-Date).ToUniversalTime().ToString('o')
            Save-WinUtilTransaction -Transaction $transaction
            throw "Restore point could not be created: $($rp.Message). Re-run with explicit allowWithoutRestorePoint=true to override."
        }
    }

    $outcomes = New-Object System.Collections.Generic.List[object]

    foreach ($d in $denied) {
        $outcomes.Add([pscustomobject]@{
            Id = $d.Id
            Status = 'BlockedByPolicy'
            Message = "Risk '$($d.Risk)' is not permitted by the '$Profile' profile."
        })
    }

    try {
        foreach ($t in $Tweaks) {
            Write-WinUtilLog -Level INFO -Message "Applying: $($t.Id)"
            $current = Get-WinUtilTweakState -Tweak $t
            if ($current.Status -eq 'AlreadyApplied') {
                $outcomes.Add([pscustomobject]@{ Id=$t.Id; Status='AlreadyApplied'; Message='No change required.' })
                continue
            }
            if ((Get-WinUtilProvider -Name $t.Provider).Kind -eq 'ReadOnly') {
                $outcomes.Add($current)
                continue
            }
            $result = Invoke-WinUtilTweakApply -Tweak $t -Transaction $transaction
            if ([string]$result.Status -eq 'VerificationFailed') { throw "Verification failed for $($t.Id): $($result.Message)" }
            $outcomes.Add($result)
        }

        $transaction.Status = 'Completed'
        $transaction.CompletedUtc = (Get-Date).ToUniversalTime().ToString('o')
        $transaction.Reversible = (@($transaction.Items | Where-Object { $_.Reversible -eq $false }).Count -eq 0)
        Save-WinUtilTransaction -Transaction $transaction

        Write-WinUtilAudit -Event 'apply.completed' -TransactionId $TransactionId -Data ([pscustomobject]@{ Items = @($outcomes | Select-Object Id, Status) })

        return [pscustomobject]@{
            Success = $true
            Message = 'Transaction completed and verified.'
            TransactionId = $transaction.TransactionId
            RestorePoint = $transaction.RestorePoint
            Items = @($outcomes)
        }
    }
    catch {
        Write-WinUtilLog -Level ERROR -Message "Transaction failed: $($_.Exception.Message)"
        $undo = Undo-WinUtilTransaction -Transaction $transaction
        Write-WinUtilAudit -Event 'apply.failed' -TransactionId $TransactionId -Data ([pscustomobject]@{ Reason = $_.Exception.Message; Rollback = $undo })
        $transaction.Status = 'RolledBackAfterFailure'
        $transaction.CompletedUtc = (Get-Date).ToUniversalTime().ToString('o')
        Save-WinUtilTransaction -Transaction $transaction
        return [pscustomobject]@{
            Success = $false
            Message = $_.Exception.Message
            TransactionId = $transaction.TransactionId
            RolledBack = $true
            RollbackResult = $undo
            Items = @($outcomes)
        }
    }
}

function Invoke-WinUtilRollback {
    param([Parameter(Mandatory)][string]$TransactionId)
    $transaction = Get-WinUtilTransaction -TransactionId $TransactionId
    $undo = Undo-WinUtilTransaction -Transaction $transaction
    $transaction.Status = 'RolledBack'
    $transaction.CompletedUtc = (Get-Date).ToUniversalTime().ToString('o')
    Save-WinUtilTransaction -Transaction $transaction
    Write-WinUtilAudit -Event 'rollback' -TransactionId $TransactionId -Data $undo
    return [pscustomobject]@{
        Success = $true
        Message = "Rollback finished. Restored: $($undo.Undone), skipped (not reversible): $($undo.Skipped), failed: $($undo.Failed)."
        TransactionId = $TransactionId
        Result = $undo
    }
}
