Set-StrictMode -Version Latest

$script:WinUtilRoot = Split-Path -Parent $PSScriptRoot
$script:DataRoot = Join-Path $env:ProgramData 'WinUtil'
$script:LogDirectory = Join-Path $script:DataRoot 'Logs'
$script:BackupDirectory = Join-Path $script:DataRoot 'Backups'
$script:TransactionDirectory = Join-Path $script:DataRoot 'Transactions'
$script:ManifestPath = $null
$script:AuditLog = Join-Path $script:LogDirectory 'audit.jsonl'

function Resolve-WinUtilManifestPath {
    # v0.1 hard-coded "<root>\..\Config\Tweaks.json", which resolved outside the
    # project in the repo layout and outside the publish folder after dotnet publish,
    # so the manifest was never found. Probe the real candidates instead.
    $candidates = @(
        (Join-Path $script:WinUtilRoot 'Config\Tweaks.json'),                 # published: <base>\Config
        (Join-Path $PSScriptRoot 'Config\Tweaks.json'),                       # side-by-side
        (Join-Path (Split-Path -Parent $script:WinUtilRoot) 'Config\Tweaks.json'),
        (Join-Path $script:DataRoot 'Config\Tweaks.json')                     # operator override
    )

    foreach ($candidate in $candidates) {
        if ($candidate -and (Test-Path -LiteralPath $candidate)) {
            return (Resolve-Path -LiteralPath $candidate).Path
        }
    }

    throw "Tweak manifest not found. Looked in: $($candidates -join '; ')"
}

foreach ($dir in @($script:LogDirectory, $script:BackupDirectory, $script:TransactionDirectory)) {
    if (-not (Test-Path -LiteralPath $dir)) {
        New-Item -LiteralPath $dir -ItemType Directory -Force | Out-Null
    }
}

function Test-WinUtilAdministrator {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Get-WinUtilOSInfo {
    $os = Get-CimInstance Win32_OperatingSystem -ErrorAction Stop
    return [pscustomobject]@{
        Caption = $os.Caption
        Version = $os.Version
        Build = [int]$os.BuildNumber
        Architecture = $os.OSArchitecture
        ComputerName = $os.CSName
    }
}

function Test-WinUtilSupportedOS {
    $os = Get-WinUtilOSInfo
    return ($os.Caption -match 'Windows 10|Windows 11')
}

function Write-WinUtilLog {
    param(
        [Parameter(Mandatory)][string]$Message,
        [ValidateSet('DEBUG','INFO','SUCCESS','WARN','ERROR')][string]$Level = 'INFO'
    )

    $file = Join-Path $script:LogDirectory ("WinUtil_{0}.log" -f (Get-Date -Format 'yyyy-MM-dd'))
    $line = '[{0}] [{1}] {2}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Level, $Message
    Add-Content -LiteralPath $file -Value $line -Encoding UTF8
}

function Read-WinUtilJsonFile {
    param([Parameter(Mandatory)][string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { throw "JSON file not found: $Path" }
    return Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json
}

function Get-WinUtilManifest {
    if (-not $script:ManifestPath) { $script:ManifestPath = Resolve-WinUtilManifestPath }
    return Read-WinUtilJsonFile -Path $script:ManifestPath
}

function Write-WinUtilAudit {
    # Append-only JSONL audit trail. One line per privileged decision, so the
    # question "what did this tool change on this machine, when, and as whom"
    # has an answer that does not depend on the UI or on the transaction files.
    param(
        [Parameter(Mandatory)][string]$Event,
        [string]$TransactionId,
        $Data
    )

    try {
        $entry = [pscustomobject]@{
            Utc           = (Get-Date).ToUniversalTime().ToString('o')
            Event         = $Event
            TransactionId = $TransactionId
            User          = [Security.Principal.WindowsIdentity]::GetCurrent().Name
            Elevated      = (Test-WinUtilAdministrator)
            Process       = $PID
            Data          = $Data
        }

        Add-Content -LiteralPath $script:AuditLog -Value ($entry | ConvertTo-Json -Depth 12 -Compress) -Encoding UTF8
    }
    catch {
        Write-WinUtilLog -Level WARN -Message "Audit write failed: $($_.Exception.Message)"
    }
}

function Get-WinUtilAuditTail {
    param([int]$Count = 200)

    if (-not (Test-Path -LiteralPath $script:AuditLog)) { return @() }

    return @(
        Get-Content -LiteralPath $script:AuditLog -Tail $Count -Encoding UTF8 |
        ForEach-Object { try { $_ | ConvertFrom-Json } catch { } } |
        Where-Object { $_ }
    )
}

function Get-WinUtilTweaksById {
    param([Parameter(Mandatory)][string[]]$Ids)
    $manifest = Get-WinUtilManifest
    $map = @{}
    foreach ($t in $manifest.Tweaks) { $map[$t.Id] = $t }
    $result = New-Object System.Collections.Generic.List[object]
    foreach ($id in $Ids) {
        if (-not $map.ContainsKey($id)) { throw "Unknown tweak id: $id" }
        $result.Add($map[$id])
    }
    return @($result)
}

function Assert-WinUtilSafePath {
    param([Parameter(Mandatory)][string]$Path)
    $full = [System.IO.Path]::GetFullPath($Path)
    $protected = @(
        [System.IO.Path]::GetPathRoot($env:SystemRoot),
        $env:SystemRoot,
        $env:ProgramFiles,
        ${env:ProgramFiles(x86)}
    ) | Where-Object { $_ }
    foreach ($p in $protected) {
        if ($full.TrimEnd('\') -ieq $p.TrimEnd('\')) { throw "Protected path: $full" }
    }
    return $full
}
