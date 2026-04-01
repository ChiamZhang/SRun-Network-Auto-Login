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

function Read-BashConfig {
    param([string] $Path)
    $vars = @{}
    if (-not (Test-Path -LiteralPath $Path)) { return $vars }
    Get-Content -LiteralPath $Path -Encoding UTF8 | ForEach-Object {
        $line = $_.Trim()
        if ($line -match '^\s*#' -or $line -eq '') { return }
        if ($line -match '^\s*([A-Za-z_][A-Za-z0-9_]*)=(.*)\s*$') {
            $k = $Matches[1]
            $raw = $Matches[2].Trim()
            if ($raw.Length -ge 2 -and $raw.StartsWith('"') -and $raw.EndsWith('"')) {
                $raw = $raw.Substring(1, $raw.Length - 2)
            }
            $vars[$k] = $raw
        }
    }
    return $vars
}

$cliAcid = $Acid
$i = 0
while ($i -lt $Rest.Length) {
    $a = $Rest[$i]
    switch -Regex ($a) {
        '^(help|-h|--help)$' {
            @'
用法:
  .\Try-Connect.ps1
  .\Try-Connect.ps1 -Acid 67
  .\Try-Connect.ps1 --acid 67
  .\Try-Connect.ps1 67

说明: 仅在 rad_user_info 报告 not_online_error 时调用 Login.ps1 login。
'@ | Write-Output
            exit 0
        }
        '^--acid$' {
            if ($i + 1 -ge $Rest.Length) { Write-Error '--acid 需要一个值' }
            $cliAcid = $Rest[$i + 1]
            $i += 2
            continue
        }
        '^--acid=' { $cliAcid = $a.Substring(7); $i++; continue }
        '^-a$' {
            if ($i + 1 -ge $Rest.Length) { Write-Error '-a 需要一个值' }
            $cliAcid = $Rest[$i + 1]
            $i += 2
            continue
        }
        default {
            if (-not $cliAcid) { $cliAcid = $a }
            else { Write-Error "未知参数: $a" }
            $i++
            continue
        }
    }
}

$cfgPath = Join-Path $ScriptDir 'config'
$cfg = Read-BashConfig $cfgPath
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
    & $loginScript login $cliAcid
} else {
    & $loginScript login
}
