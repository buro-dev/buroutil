Set-StrictMode -Version Latest

function Register-WinUtilAgentTask {
    param([Parameter(Mandatory)][string]$ExecutablePath)

    if (-not (Test-WinUtilAdministrator)) { throw 'Administrator privileges required.' }

    $user = [Security.Principal.WindowsIdentity]::GetCurrent().Name
    $action = New-ScheduledTaskAction -Execute $ExecutablePath -Argument '--background'
    $trigger = New-ScheduledTaskTrigger -AtLogOn -User $user
    $settings = New-ScheduledTaskSettingsSet -Hidden -StartWhenAvailable -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries
    $principal = New-ScheduledTaskPrincipal -UserId $user -LogonType Interactive -RunLevel Highest

    Register-ScheduledTask -TaskName 'WinUtil NG Agent' -Action $action -Trigger $trigger -Settings $settings -Principal $principal -Description 'WinUtil NG local browser agent.' -Force | Out-Null
}

function Register-WinUtilSystemStartupTask {
    param([Parameter(Mandatory)][string]$ExecutablePath)

    if (-not (Test-WinUtilAdministrator)) { throw 'Administrator privileges required.' }

    $action = New-ScheduledTaskAction -Execute $ExecutablePath -Argument '--background --scope system'
    $trigger = New-ScheduledTaskTrigger -AtStartup
    $settings = New-ScheduledTaskSettingsSet -Hidden -StartWhenAvailable -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries
    $principal = New-ScheduledTaskPrincipal -UserId 'SYSTEM' -LogonType ServiceAccount -RunLevel Highest

    Register-ScheduledTask -TaskName 'WinUtil NG System Maintenance' -Action $action -Trigger $trigger -Settings $settings -Principal $principal -Description 'WinUtil NG system maintenance task.' -Force | Out-Null
}

function Unregister-WinUtilTasks {
    foreach ($name in @('WinUtil NG Agent', 'WinUtil NG System Maintenance')) {
        Unregister-ScheduledTask -TaskName $name -Confirm:$false -ErrorAction SilentlyContinue
    }
}
