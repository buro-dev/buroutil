Set-StrictMode -Version Latest

function New-WinUtilTransaction {
    param(
        [Parameter(Mandatory)][string]$TransactionId,
        [Parameter(Mandatory)][string[]]$TweakIds
    )

    $tx = [pscustomobject]@{
        TransactionId = $TransactionId
        CreatedUtc = (Get-Date).ToUniversalTime().ToString('o')
        CompletedUtc = $null
        Status = 'Created'
        Reversible = $true
        TweakIds = @($TweakIds)
        Items = @()
        RestorePoint = $false
        RestorePointMessage = $null
    }

    Save-WinUtilTransaction -Transaction $tx
    return $tx
}

function Get-WinUtilTransactionPath {
    param([Parameter(Mandatory)][string]$TransactionId)
    return Join-Path $script:TransactionDirectory ("{0}.json" -f $TransactionId)
}

function Save-WinUtilTransaction {
    param([Parameter(Mandatory)]$Transaction)
    $path = Get-WinUtilTransactionPath -TransactionId $Transaction.TransactionId
    $Transaction | ConvertTo-Json -Depth 30 | Set-Content -LiteralPath $path -Encoding UTF8

    $summaryPath = Join-Path $script:TransactionDirectory ("{0}.summary.json" -f $Transaction.TransactionId)
    $summary = [pscustomobject]@{
        TransactionId = $Transaction.TransactionId
        CreatedUtc = $Transaction.CreatedUtc
        CompletedUtc = $Transaction.CompletedUtc
        Status = $Transaction.Status
        Reversible = [bool]$Transaction.Reversible
        TweakIds = @($Transaction.TweakIds)
    }
    $summary | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $summaryPath -Encoding UTF8
}

function Get-WinUtilTransaction {
    param([Parameter(Mandatory)][string]$TransactionId)
    $path = Get-WinUtilTransactionPath -TransactionId $TransactionId
    if (-not (Test-Path -LiteralPath $path)) { throw "Transaction not found: $TransactionId" }
    return Get-Content -LiteralPath $path -Raw -Encoding UTF8 | ConvertFrom-Json
}

function Add-WinUtilTransactionItem {
    param(
        [Parameter(Mandatory)]$Transaction,
        [Parameter(Mandatory)]$Item
    )
    $list = @($Transaction.Items)
    $list += $Item
    $Transaction.Items = $list
    Save-WinUtilTransaction -Transaction $Transaction
}
