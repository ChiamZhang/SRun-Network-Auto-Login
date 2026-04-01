#Requires -Version 5.1
<#
.SYNOPSIS
  检测未在线则登录（对应 try-connect.sh）
#>
[CmdletBinding()]
param(
    [Alias('a')]
    [string] $Acid,

    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]] $Rest
)

$ErrorActionPreference = 'Stop'
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $ScriptDir '_SRunCommon.ps1')

if ($Rest.Count -gt 0 -and $Rest[0] -match '^(help|-h|--help)$') {
    @'
用法:
  .\Try-Connect.ps1
  .\Try-Connect.ps1 -Acid 67
  .\Try-Connect.ps1 --acid 67
  .\Try-Connect.ps1 --acid=67
  .\Try-Connect.ps1 67

说明: 仅在 rad_user_info 报告 not_online_error 时调用 Login.ps1 login。
'@ | Write-Output
    exit 0
}

$tailArgs = @($Rest | ForEach-Object { $_ })
try {
    $parsed = Parse-SrunAcidTailArgs -Args $tailArgs
} catch {
    Write-Error $_.Exception.Message
}
$cliAcid = if ($Acid) { $Acid } elseif ($parsed) { $parsed } else { '' }

$cfgPath = Join-Path $ScriptDir 'config'
$cfg = Read-SrunBashConfig $cfgPath
$SRUN_SCHEME = if ($cfg['SRUN_SCHEME']) { $cfg['SRUN_SCHEME'] } else { 'https' }
$SRUN_HOST = if ($cfg['SRUN_HOST']) { $cfg['SRUN_HOST'] } else { 'gw.buaa.edu.cn' }
$SRUN_RAD_USER_INFO_URL = if ($cfg['SRUN_RAD_USER_INFO_URL']) { $cfg['SRUN_RAD_USER_INFO_URL'] } else { "${SRUN_SCHEME}://${SRUN_HOST}/cgi-bin/rad_user_info" }

try {
    $online = & curl.exe -sS -k --noproxy '*' $SRUN_RAD_USER_INFO_URL 2>$null
} catch {
    $online = ''
}

if ($online -notmatch 'not_online_error') {
    $first = ($online -split ',')[0]
    Write-Host "online: $first"
    exit 0
}

$loginScript = Join-Path $ScriptDir 'Login.ps1'
if ($cliAcid) {
    & $loginScript login --acid $cliAcid
} else {
    & $loginScript login
}
