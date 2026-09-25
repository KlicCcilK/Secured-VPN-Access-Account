param(
    [Parameter(Mandatory = $true)]
    [string]$XmlPath,

    [switch]$Remove
)

$ErrorActionPreference = 'Stop'
$logPath = 'C:\Temp\apply-assigned-access.log'

function Write-Log {
    param([string]$Message)
    $line = '{0}  {1}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Message
    $dir = Split-Path -Parent $logPath
    if (-not (Test-Path -LiteralPath $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }
    Add-Content -LiteralPath $logPath -Value $line
    Write-Host $Message
}

$namespace = 'root\cimv2\mdm\dmmap'
$className = 'MDM_AssignedAccess'

function Test-IsSystem {
    $sid = [System.Security.Principal.WindowsIdentity]::GetCurrent().User.Value
    return $sid -eq 'S-1-5-18'
}

Write-Log "Apply-AssignedAccess started. Remove=$Remove XmlPath=$XmlPath User=$([System.Security.Principal.WindowsIdentity]::GetCurrent().Name)"

if (-not (Test-IsSystem)) {
    Write-Log 'WARNING: Not running as SYSTEM. Assigned Access apply may fail.'
}

$obj = Get-CimInstance -Namespace $namespace -ClassName $className
if (-not $obj) {
    throw "CIM class $className was not found in $namespace."
}

if ($Remove) {
    $obj.Configuration = $null
    Set-CimInstance -CimInstance $obj
    Write-Log 'Assigned Access configuration removed. Sign out of VPNaccess for it to take effect.'
    return
}

if (-not (Test-Path -LiteralPath $XmlPath)) {
    throw "XML file not found: $XmlPath"
}

$xml = Get-Content -LiteralPath $XmlPath -Raw -Encoding UTF8
if ([string]::IsNullOrWhiteSpace($xml)) {
    throw "XML file is empty: $XmlPath"
}

$obj.Configuration = [System.Net.WebUtility]::HtmlEncode($xml)
Set-CimInstance -CimInstance $obj

Write-Log "Assigned Access applied from $XmlPath"
Write-Log 'Sign out of VPNaccess (or reboot) so the profile takes effect.'
