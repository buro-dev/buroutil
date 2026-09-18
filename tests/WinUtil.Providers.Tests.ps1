#Requires -Modules Pester
# Contract tests for the WinUtil NG provider framework.
#   Invoke-Pester .\tests\WinUtil.Providers.Tests.ps1
# Registry round-trip tests write only under HKCU:\Software\WinUtilNGTests.

BeforeAll {
    $psRoot = Join-Path (Split-Path -Parent $PSScriptRoot) 'PowerShell'
    foreach ($f in 'Core', 'Registry', 'Backup', 'Restore', 'Operations', 'WindowsUpdate', 'Providers', 'Engine') {
        . (Join-Path $psRoot "$f.ps1")
    }
    $script:manifest = Get-WinUtilManifest
}

Describe 'Manifest resolution' {
    It 'finds Config\Tweaks.json without escaping the project root' {
        $script:manifest.SchemaVersion | Should -Be 1
        $script:manifest.Tweaks.Count | Should -BeGreaterThan 0
    }
}

Describe 'Provider registry' {
    It 'exposes every provider referenced by the manifest' {
        foreach ($id in ($script:manifest.Tweaks.Provider | Select-Object -Unique)) {
            { Get-WinUtilProvider -Name $id } | Should -Not -Throw
        }
    }

    It 'rejects an unknown provider' {
        { Get-WinUtilProvider -Name 'DoesNotExist' } | Should -Throw
    }

    It 'gives every non-ReadOnly provider an Apply block' {
        foreach ($p in Get-WinUtilProviderCatalog) {
            if ($p.Kind -ne 'ReadOnly') {
                (Get-WinUtilProvider -Name $p.Name).Apply | Should -Not -BeNullOrEmpty
            }
        }
    }

    It 'never marks a tweak reversible when its provider cannot roll back' {
        foreach ($t in $script:manifest.Tweaks) {
            if ($t.Reversible) {
                (Get-WinUtilProvider -Name $t.Provider).Rollback | Should -Not -BeNullOrEmpty -Because "$($t.Id) claims to be reversible"
            }
        }
    }

    It 'refuses to register a mutating provider without Apply' {
        { Register-WinUtilProvider -Name 'Broken' -Kind State -Detect { } } | Should -Throw
    }
}

Describe 'Risk profiles' {
    It 'maps profiles to the documented risk sets' {
        Get-WinUtilAllowedRisk -Profile 'safe'       | Should -Be @('Low')
        Get-WinUtilAllowedRisk -Profile 'balanced'   | Should -Be @('Low', 'Medium')
        Get-WinUtilAllowedRisk -Profile 'aggressive' | Should -Be @('Low', 'Medium', 'High')
    }

    It 'rejects an unknown profile' {
        { Get-WinUtilAllowedRisk -Profile 'yolo' } | Should -Throw
    }
}

Describe 'Registry provider round-trip' -Skip:(-not $IsWindows) {
    BeforeAll {
        $script:testPath = 'HKCU:\Software\WinUtilNGTests'
        $script:tweak = [pscustomobject]@{
            Id = 'Test.Value'; Provider = 'Registry'; Reversible = $true
            Settings = [pscustomobject]@{
                RegistryPath = $script:testPath; ValueName = 'Sample'
                DesiredValue = 1; PropertyType = 'DWord'
            }
        }
    }
    AfterAll { Remove-Item -LiteralPath $script:testPath -Recurse -Force -ErrorAction SilentlyContinue }

    It 'detects a missing value as ChangeRequired' {
        Remove-Item -LiteralPath $script:testPath -Recurse -Force -ErrorAction SilentlyContinue
        (Get-WinUtilTweakState -Tweak $script:tweak).Status | Should -Be 'ChangeRequired'
    }

    It 'applies, verifies, then restores the exact previous state' {
        Ensure-RegistryKey -Path $script:testPath
        Set-WinUtilRegistryValue -Path $script:testPath -Name 'Sample' -Value 7 -PropertyType DWord

        $tx = New-WinUtilTransaction -TransactionId ([guid]::NewGuid().ToString('N')) -TweakIds @('Test.Value')
        $result = Invoke-WinUtilTweakApply -Tweak $script:tweak -Transaction $tx

        $result.Status | Should -Be 'Applied'
        $result.Verified | Should -BeTrue
        (Get-WinUtilRegistryValueState -Path $script:testPath -Name 'Sample').Value | Should -Be 1

        Undo-WinUtilTransaction -Transaction $tx | Out-Null
        (Get-WinUtilRegistryValueState -Path $script:testPath -Name 'Sample').Value | Should -Be 7
    }

    It 'removes a value that did not exist before the change' {
        Remove-Item -LiteralPath $script:testPath -Recurse -Force -ErrorAction SilentlyContinue

        $tx = New-WinUtilTransaction -TransactionId ([guid]::NewGuid().ToString('N')) -TweakIds @('Test.Value')
        Invoke-WinUtilTweakApply -Tweak $script:tweak -Transaction $tx | Out-Null
        Undo-WinUtilTransaction -Transaction $tx | Out-Null

        (Get-WinUtilRegistryValueState -Path $script:testPath -Name 'Sample').Exists | Should -BeFalse
    }
}

Describe 'Apply planner' -Skip:(-not $IsWindows) {
    It 'reports profile-blocked tweaks instead of dropping them' {
        $plan = Get-WinUtilApplyPlan -Ids @('Privacy.Telemetry', 'Services.DeliveryOptimizationManual') -Profile 'safe'
        $plan.TotalRequested | Should -Be 2
        $plan.BlockedCount | Should -Be 1
        ($plan.Items | Where-Object Id -eq 'Services.DeliveryOptimizationManual').Status | Should -Be 'BlockedByPolicy'
    }
}
