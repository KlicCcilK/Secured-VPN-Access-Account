[CmdletBinding()]
param(
    [string]$UserName = 'VPNaccess',
    [string]$GroupName = 'Restricted User Experience',
    [string]$Password,
    [string]$PsToolsZip,
    [switch]$RemoveAssignedAccess
)

$ErrorActionPreference = 'Stop'
$SourceDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$ToolsRoot = 'C:\Tools'
$PsToolsDir = 'C:\Tools\PsTools'
$TempDir = 'C:\Temp'
$LogPath = Join-Path $TempDir 'vpnaccess-install.log'
$XmlDest = Join-Path $TempDir 'vpn-restricted-accounts.xml'
$ApplyDest = Join-Path $TempDir 'Apply-AssignedAccess.ps1'

function Write-Log {
    param(
        [string]$Message,
        [ValidateSet('INFO', 'WARN', 'ERROR')]$Level = 'INFO'
    )
    $line = '{0}  [{1}] {2}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Level, $Message
    Add-Content -LiteralPath $LogPath -Value $line
    switch ($Level) {
        'ERROR' { Write-Host $line -ForegroundColor Red }
        'WARN'  { Write-Host $line -ForegroundColor Yellow }
        default { Write-Host $line }
    }
}

function Test-IsAdmin {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    $p = [Security.Principal.WindowsPrincipal]$id
    return $p.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Hide-OutlookTaskbarPin {
    param([string]$AccountName)

    $explorerPol = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\Explorer'
    if (-not (Test-Path $explorerPol)) {
        New-Item -Path $explorerPol -Force | Out-Null
    }
    New-ItemProperty -Path $explorerPol -Name 'HideOutlookPin' -PropertyType DWord -Value 1 -Force | Out-Null
    Write-Log 'Set HideOutlookPin machine policy'

    $cloudPol = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\CloudContent'
    if (-not (Test-Path $cloudPol)) {
        New-Item -Path $cloudPol -Force | Out-Null
    }
    New-ItemProperty -Path $cloudPol -Name 'DisableCloudOptimizedContent' -PropertyType DWord -Value 1 -Force | Out-Null
    Write-Log 'Set DisableCloudOptimizedContent machine policy'

    $user = Get-LocalUser -Name $AccountName -ErrorAction SilentlyContinue
    if (-not $user) { return }

    $userSid = $user.Sid.Value
    $hiveLoaded = $false
    $userExplorer = "Registry::HKEY_USERS\$userSid\Software\Policies\Microsoft\Windows\Explorer"

    try {
        if (-not (Test-Path "Registry::HKEY_USERS\$userSid\Software")) {
            $dat = "C:\Users\$AccountName\NTUSER.DAT"
            if (Test-Path -LiteralPath $dat) {
                & reg.exe load "HKU\$userSid" $dat | Out-Null
                if ($LASTEXITCODE -eq 0) { $hiveLoaded = $true }
            }
        }

        if (Test-Path "Registry::HKEY_USERS\$userSid\Software") {
            if (-not (Test-Path $userExplorer)) {
                New-Item -Path $userExplorer -Force | Out-Null
            }
            New-ItemProperty -Path $userExplorer -Name 'HideOutlookPin' -PropertyType DWord -Value 1 -Force | Out-Null
            Write-Log "Set HideOutlookPin for $AccountName"
        }
        else {
            Write-Log "VPNaccess profile hive not available yet; machine HideOutlookPin still applies" 'WARN'
        }
    }
    catch {
        Write-Log "Could not write per-user HideOutlookPin: $($_.Exception.Message)" 'WARN'
    }
    finally {
        if ($hiveLoaded) {
            [gc]::Collect()
            Start-Sleep -Seconds 1
            & reg.exe unload "HKU\$userSid" | Out-Null
        }
    }
}

function Set-RegistryDword {
    param([string]$Path, [string]$Name, [int]$Value)
    if (-not (Test-Path $Path)) {
        New-Item -Path $Path -Force | Out-Null
    }
    New-ItemProperty -Path $Path -Name $Name -PropertyType DWord -Value $Value -Force | Out-Null
}

function Set-VpnAccessTrayLockdown {
    param([string]$HiveRoot)

    Set-RegistryDword -Path "$HiveRoot\Software\Microsoft\Windows\CurrentVersion\Policies\Explorer" -Name 'NoTrayItemsDisplay' -Value 1
    Set-RegistryDword -Path "$HiveRoot\Software\Microsoft\Windows\CurrentVersion\Policies\Explorer" -Name 'HideSCAHealth' -Value 1
    Set-RegistryDword -Path "$HiveRoot\Software\Microsoft\Windows\CurrentVersion\Policies\Explorer" -Name 'HideSCANetwork' -Value 1
    Set-RegistryDword -Path "$HiveRoot\Software\Microsoft\Windows\CurrentVersion\Policies\Explorer" -Name 'HideSCAVolume' -Value 1
    Set-RegistryDword -Path "$HiveRoot\Software\Microsoft\Windows\CurrentVersion\Policies\Explorer" -Name 'HideSCAPower' -Value 1
    Set-RegistryDword -Path "$HiveRoot\Software\Policies\Microsoft\Windows\Explorer" -Name 'DisableNotificationCenter' -Value 1
    Set-RegistryDword -Path "$HiveRoot\Software\Policies\Microsoft\Windows\Explorer" -Name 'HideSCAHealth' -Value 1
    Set-RegistryDword -Path "$HiveRoot\SOFTWARE\Classes\Local Settings\Software\Microsoft\Windows\CurrentVersion\TrayNotify" -Name 'SystemTrayChevronVisibility' -Value 0
    Set-RegistryDword -Path "$HiveRoot\Software\Microsoft\Windows\CurrentVersion\PushNotifications" -Name 'ToastEnabled' -Value 0
    Set-RegistryDword -Path "$HiveRoot\Software\Policies\Microsoft\Windows\CurrentVersion\PushNotifications" -Name 'NoToastApplicationNotification' -Value 1
    Set-RegistryDword -Path "$HiveRoot\Software\Policies\Microsoft\Windows Defender Security Center\Systray" -Name 'HideSystray' -Value 1
    Set-RegistryDword -Path "$HiveRoot\Software\Microsoft\Windows\CurrentVersion\Notifications\Settings" -Name 'NOC_GLOBAL_SETTING_TOASTS_ENABLED' -Value 0
}

function Register-VpnAccessTrayLockdownTask {
    param(
        [string]$AccountName,
        [string]$UserSid
    )

    $scriptPath = Join-Path $TempDir 'Lock-VpnAccessTray.ps1'
    $script = @"
`$sid = '$UserSid'
`$root = "Registry::HKEY_USERS\`$sid"
for (`$i = 0; `$i -lt 30; `$i++) {
    if (Test-Path "`$root\Software") { break }
    Start-Sleep -Seconds 1
}
if (-not (Test-Path "`$root\Software")) { return }
function Set-Dword(`$Path, `$Name, `$Value) {
    if (-not (Test-Path `$Path)) { New-Item -Path `$Path -Force | Out-Null }
    New-ItemProperty -Path `$Path -Name `$Name -PropertyType DWord -Value `$Value -Force | Out-Null
}
Set-Dword "`$root\Software\Microsoft\Windows\CurrentVersion\Policies\Explorer" 'NoTrayItemsDisplay' 1
Set-Dword "`$root\Software\Microsoft\Windows\CurrentVersion\Policies\Explorer" 'HideSCAHealth' 1
Set-Dword "`$root\Software\Microsoft\Windows\CurrentVersion\Policies\Explorer" 'HideSCANetwork' 1
Set-Dword "`$root\Software\Microsoft\Windows\CurrentVersion\Policies\Explorer" 'HideSCAVolume' 1
Set-Dword "`$root\Software\Microsoft\Windows\CurrentVersion\Policies\Explorer" 'HideSCAPower' 1
Set-Dword "`$root\Software\Policies\Microsoft\Windows\Explorer" 'DisableNotificationCenter' 1
Set-Dword "`$root\Software\Policies\Microsoft\Windows\Explorer" 'HideSCAHealth' 1
Set-Dword "`$root\Software\Microsoft\Windows\CurrentVersion\PushNotifications" 'ToastEnabled' 0
Set-Dword "`$root\Software\Policies\Microsoft\Windows\CurrentVersion\PushNotifications" 'NoToastApplicationNotification' 1
Set-Dword "`$root\Software\Policies\Microsoft\Windows Defender Security Center\Systray" 'HideSystray' 1
Set-Dword "`$root\Software\Microsoft\Windows\CurrentVersion\Notifications\Settings" 'NOC_GLOBAL_SETTING_TOASTS_ENABLED' 0
Set-Dword "`$root\SOFTWARE\Classes\Local Settings\Software\Microsoft\Windows\CurrentVersion\TrayNotify" 'SystemTrayChevronVisibility' 0
Get-Process -Name SecurityHealthSystray -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
"@
    Set-Content -LiteralPath $scriptPath -Value $script -Encoding UTF8

    $taskName = 'VPNAccess-TrayLockdown'
    Unregister-ScheduledTask -TaskName $taskName -Confirm:$false -ErrorAction SilentlyContinue
    $action = New-ScheduledTaskAction -Execute "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe" -Argument "-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$scriptPath`""
    $trigger = New-ScheduledTaskTrigger -AtLogOn -User "$env:COMPUTERNAME\$AccountName"
    $principal = New-ScheduledTaskPrincipal -UserId 'SYSTEM' -LogonType ServiceAccount -RunLevel Highest
    $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -MultipleInstances IgnoreNew
    Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger -Principal $principal -Settings $settings -Force | Out-Null
    Write-Log "Registered $taskName to hide the tray at $AccountName logon"
}

function Update-FortiClientStartPin {
    param([string]$XmlPath)

    $lnk = Get-ChildItem "$env:ProgramData\Microsoft\Windows\Start Menu\Programs" -Recurse -Filter '*Forti*.lnk' -ErrorAction SilentlyContinue |
        Select-Object -First 1
    if (-not $lnk) {
        Write-Log 'No FortiClient Start shortcut found; leaving XML StartPins unchanged' 'WARN'
        return
    }

    $relative = $lnk.FullName.Replace("$env:ProgramData\", '%ALLUSERSPROFILE%\').Replace('\', '\\')
    $xml = Get-Content -LiteralPath $XmlPath -Raw -Encoding UTF8
    $updated = [regex]::Replace(
        $xml,
        '"desktopAppLink"\s*:\s*"[^"]+"',
        ('"desktopAppLink":"' + $relative + '"')
    )
    Set-Content -LiteralPath $XmlPath -Value $updated -Encoding UTF8
    Write-Log "Start pin set to $($lnk.FullName)"
}

function Add-MachinePath {
    param([string]$Folder)
    $current = [Environment]::GetEnvironmentVariable('Path', 'Machine')
    $parts = $current -split ';' | Where-Object { $_ -and $_.Trim() }
    if ($parts -contains $Folder) {
        Write-Log "PATH already contains $Folder"
        return
    }
    $new = ($parts + $Folder) -join ';'
    [Environment]::SetEnvironmentVariable('Path', $new, 'Machine')
    $env:Path = $new + ';' + $env:Path
    Write-Log "Added $Folder to system PATH"
}

function Find-PsToolsZip {
    if ($PsToolsZip -and (Test-Path -LiteralPath $PsToolsZip)) {
        return (Resolve-Path -LiteralPath $PsToolsZip).Path
    }
    $candidates = @(
        (Join-Path $SourceDir 'PsTools.zip'),
        (Join-Path $SourceDir 'PSTools.zip'),
        (Join-Path $TempDir 'PsTools.zip'),
        (Join-Path $TempDir 'PSTools.zip')
    )
    foreach ($c in $candidates) {
        if (Test-Path -LiteralPath $c) {
            return (Resolve-Path -LiteralPath $c).Path
        }
    }
    return $null
}

function Install-PsTools {
    if (Test-Path -LiteralPath (Join-Path $PsToolsDir 'PsExec.exe')) {
        Write-Log "PsExec already present at $PsToolsDir"
        Unblock-File -Path (Join-Path $PsToolsDir '*.exe') -ErrorAction SilentlyContinue
        return
    }

    $zip = Find-PsToolsZip
    if (-not $zip) {
        throw 'PsTools.zip was not found. Place it next to install.cmd or in C:\Temp.'
    }

    Write-Log "Extracting $zip to $PsToolsDir"
    New-Item -ItemType Directory -Path $PsToolsDir -Force | Out-Null
    Expand-Archive -LiteralPath $zip -DestinationPath $PsToolsDir -Force
    Unblock-File -Path (Join-Path $PsToolsDir '*.exe') -ErrorAction SilentlyContinue

    if (-not (Test-Path -LiteralPath (Join-Path $PsToolsDir 'PsExec.exe'))) {
        throw "Extracted PsTools zip, but PsExec.exe was not found in $PsToolsDir"
    }
}

function Invoke-AsSystem {
    param([string]$ArgumentList)

    $taskName = 'VPNAccess-ApplyAssignedAccess'
    Unregister-ScheduledTask -TaskName $taskName -Confirm:$false -ErrorAction SilentlyContinue

    $action = New-ScheduledTaskAction -Execute "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe" -Argument $ArgumentList
    $principal = New-ScheduledTaskPrincipal -UserId 'SYSTEM' -LogonType ServiceAccount -RunLevel Highest
    $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -MultipleInstances IgnoreNew
    Register-ScheduledTask -TaskName $taskName -Action $action -Principal $principal -Settings $settings -Force | Out-Null

    Write-Log "Starting SYSTEM task $taskName"
    Start-ScheduledTask -TaskName $taskName

    $timeout = (Get-Date).AddMinutes(2)
    do {
        Start-Sleep -Seconds 2
        $info = Get-ScheduledTaskInfo -TaskName $taskName
        $state = (Get-ScheduledTask -TaskName $taskName).State
        if ($state -eq 'Ready' -and $info.LastRunTime -gt (Get-Date).AddMinutes(-5)) {
            break
        }
    } while ((Get-Date) -lt $timeout)

    $code = (Get-ScheduledTaskInfo -TaskName $taskName).LastTaskResult
    Unregister-ScheduledTask -TaskName $taskName -Confirm:$false -ErrorAction SilentlyContinue
    return $code
}

# --- start ---
New-Item -ItemType Directory -Path $TempDir -Force | Out-Null
New-Item -ItemType Directory -Path $ToolsRoot -Force | Out-Null
Write-Log '=== VPN access installer started ==='
Write-Log "Source directory: $SourceDir"

if (-not (Test-IsAdmin)) {
    throw 'This installer must run from an elevated Administrator prompt.'
}

$xmlSource = Join-Path $SourceDir 'vpn-restricted-accounts.xml'
$applySource = Join-Path $SourceDir 'Apply-AssignedAccess.ps1'
foreach ($required in @($xmlSource, $applySource)) {
    if (-not (Test-Path -LiteralPath $required)) {
        throw "Missing package file: $required"
    }
}

Copy-Item -LiteralPath $xmlSource -Destination $XmlDest -Force
Copy-Item -LiteralPath $applySource -Destination $ApplyDest -Force
Write-Log "Copied XML and apply script to $TempDir"
(Get-Content -LiteralPath $XmlDest -Raw -Encoding UTF8) -replace '<Account>[^<]+</Account>', "<Account>$UserName</Account>" |
    Set-Content -LiteralPath $XmlDest -Encoding UTF8
Write-Log "Assigned Access target account set to $UserName"
Update-FortiClientStartPin -XmlPath $XmlDest

Install-PsTools
Add-MachinePath -Folder $PsToolsDir

if (Get-LocalUser -Name $UserName -ErrorAction SilentlyContinue) {
    Write-Log "User already exists: $UserName"
    if ($Password) {
        $secure = ConvertTo-SecureString $Password -AsPlainText -Force
        Set-LocalUser -Name $UserName -Password $secure -PasswordNeverExpires $true
        Write-Log "Updated password for $UserName"
    }
} else {
    if (-not $Password) {
        $secure = Read-Host -AsSecureString "Enter password for new local user $UserName"
    } else {
        $secure = ConvertTo-SecureString $Password -AsPlainText -Force
    }

    New-LocalUser -Name $UserName `
        -Password $secure `
        -FullName 'VPN Access' `
        -Description 'VPN FortiClient account' `
        -PasswordNeverExpires `
        -UserMayNotChangePassword | Out-Null
    Write-Log "Created local user: $UserName"
}

$usersGroup = Get-LocalGroupMember -Group 'Users' -ErrorAction SilentlyContinue | Where-Object { $_.Name -like "*\$UserName" }
if (-not $usersGroup) {
    Add-LocalGroupMember -Group 'Users' -Member $UserName
    Write-Log "Added $UserName to Users"
}

$pol = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System'
if (-not (Test-Path $pol)) {
    New-Item -Path $pol -Force | Out-Null
}
New-ItemProperty -Path $pol -Name 'HideFastUserSwitching' -PropertyType DWord -Value 0 -Force | Out-Null
Write-Log 'Enabled fast user switching'

$arg = if ($RemoveAssignedAccess) {
    "-NoProfile -ExecutionPolicy Bypass -File `"$ApplyDest`" -XmlPath `"$XmlDest`" -Remove"
} else {
    "-NoProfile -ExecutionPolicy Bypass -File `"$ApplyDest`" -XmlPath `"$XmlDest`""
}

$result = Invoke-AsSystem -ArgumentList $arg
Write-Log "SYSTEM apply task result: $result"

if ($result -ne 0) {
    Write-Log 'Scheduled task apply did not return 0. Trying PsExec fallback.' 'WARN'
    $psexec = Join-Path $PsToolsDir 'PsExec.exe'
    if (Test-Path -LiteralPath $psexec) {
        $pArgs = @(
            '-accepteula', '-h', '-s',
            "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe",
            '-NoProfile', '-ExecutionPolicy', 'Bypass',
            '-File', $ApplyDest,
            '-XmlPath', $XmlDest
        )
        if ($RemoveAssignedAccess) { $pArgs += '-Remove' }
        $proc = Start-Process -FilePath $psexec -ArgumentList $pArgs -Wait -PassThru -NoNewWindow
        Write-Log "PsExec exit code: $($proc.ExitCode)"
        if ($proc.ExitCode -ne 0) {
            throw "Assigned Access apply failed. See $TempDir\apply-assigned-access.log"
        }
    } else {
        throw "Assigned Access apply failed. See $LogPath and $TempDir\apply-assigned-access.log"
    }
}

if (-not $RemoveAssignedAccess) {
    Unregister-ScheduledTask -TaskName 'VPNAccess-RemoveOutlook' -Confirm:$false -ErrorAction SilentlyContinue
    Hide-OutlookTaskbarPin -AccountName $UserName

    $userSid = (Get-LocalUser -Name $UserName).Sid.Value
    $hiveRoot = "Registry::HKEY_USERS\$userSid"
    $loaded = $false
    try {
        if (-not (Test-Path "$hiveRoot\Software")) {
            $dat = "C:\Users\$UserName\NTUSER.DAT"
            if (Test-Path -LiteralPath $dat) {
                & reg.exe load "HKU\$userSid" $dat | Out-Null
                if ($LASTEXITCODE -eq 0) { $loaded = $true }
            }
        }
        if (Test-Path "$hiveRoot\Software") {
            Set-VpnAccessTrayLockdown -HiveRoot $hiveRoot
            Write-Log "Applied tray lockdown to $UserName hive"
        }
        else {
            Write-Log 'VPNaccess hive not loaded yet; tray lockdown will apply at first logon' 'WARN'
        }
    }
    catch {
        Write-Log "Tray lockdown hive write skipped: $($_.Exception.Message)" 'WARN'
    }
    finally {
        if ($loaded) {
            [gc]::Collect()
            Start-Sleep -Seconds 1
            & reg.exe unload "HKU\$userSid" | Out-Null
        }
    }

    Register-VpnAccessTrayLockdownTask -AccountName $UserName -UserSid $userSid
}

Write-Log '=== Install completed ==='
Write-Host ''
Write-Host "User:  $UserName"
Write-Host "Group: $GroupName"
Write-Host "Log:   $LogPath"
Write-Host ''
Write-Host 'Sign out of VPNaccess (or reboot) before testing the restricted profile.'
Write-Host 'Use the FortiClient tile on Start to connect. The system tray is hidden for this account.'
