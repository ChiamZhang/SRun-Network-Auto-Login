#Requires -Version 5.1
<#
.SYNOPSIS
  周期性检测并掉线重连（对应 protect-connect.sh）
.DESCRIPTION
  间隔: 环境变量 PROTECT_INTERVAL 优先，否则读取 config 中 PROTECT_INTERVAL，默认 3600 秒。
#>
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

$savedPi = $env:PROTECT_INTERVAL
$cfgPath = Join-Path $ScriptDir 'config'
$cfg = Read-BashConfig $cfgPath
$INTERVAL = if ($null -ne $savedPi -and $savedPi -ne '') { $savedPi } elseif ($cfg['PROTECT_INTERVAL']) { $cfg['PROTECT_INTERVAL'] } else { '3600' }

$SRUN_SCHEME = if ($cfg['SRUN_SCHEME']) { $cfg['SRUN_SCHEME'] } else { 'https' }
$SRUN_HOST = if ($cfg['SRUN_HOST']) { $cfg['SRUN_HOST'] } else { 'gw.buaa.edu.cn' }
$SRUN_RAD_USER_INFO_URL = if ($cfg['SRUN_RAD_USER_INFO_URL']) { $cfg['SRUN_RAD_USER_INFO_URL'] } else { "${SRUN_SCHEME}://${SRUN_HOST}/cgi-bin/rad_user_info" }

function Test-Offline {
    try {
        $out = & curl.exe -sS -k --noproxy '*' $SRUN_RAD_USER_INFO_URL 2>$null
    } catch {
        return $true
    }
    return ($out -match 'not_online_error')
}

function Write-Log([string] $Msg) {
    Write-Host ("[{0}] {1}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Msg)
}

if ($INTERVAL -notmatch '^\d+$' -or [int]$INTERVAL -lt 60) {
    Write-Error 'PROTECT_INTERVAL 须为不小于 60 的整数（秒）'
}

$loginScript = Join-Path $ScriptDir 'Login.ps1'
Write-Log "protect-connect 启动，检测间隔 ${INTERVAL}s。Ctrl+C 结束。"

while ($true) {
    if (Test-Offline) {
        Write-Log '未在线，尝试登录…'
        try {
            & $loginScript login
            if ($LASTEXITCODE -ne 0 -and $null -ne $LASTEXITCODE) {
                Write-Log "Login.ps1 退出码 $LASTEXITCODE，${INTERVAL}s 后再检测"
            }
        } catch {
            Write-Log "登录异常: $_，${INTERVAL}s 后再检测"
        }
    } else {
        Write-Log '仍在线'
    }
    Start-Sleep -Seconds ([int]$INTERVAL)
}
