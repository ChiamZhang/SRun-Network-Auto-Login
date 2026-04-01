#Requires -Version 5.1
<#
.SYNOPSIS
  SRun 校园网登录/注销（Windows / PowerShell），与仓库根目录 login.sh 行为对齐。
.DESCRIPTION
  依赖：PowerShell 5.1+、系统自带的 curl.exe（Windows 10+ 自带）。
  配置：将 config.example 复制为与本脚本同目录的 config（bash 风格 KEY="value"）。
  用法:
    .\Login.ps1 login
    .\Login.ps1 logout
    .\Login.ps1 login -Acid 67
    .\Login.ps1 help
#>
[CmdletBinding()]
param(
    [Parameter(Position = 0)]
    [ValidateSet('login', 'logout', 'help')]
    [string] $Command = 'login',

    [Parameter(Position = 1)]
    [string] $AcidArg,

    [Alias('a')]
    [string] $Acid
)

$ErrorActionPreference = 'Stop'
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$ConfigPath = Join-Path $ScriptDir 'config'

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
            elseif ($raw.Length -ge 2 -and $raw.StartsWith("'") -and $raw.EndsWith("'")) {
                $raw = $raw.Substring(1, $raw.Length - 2)
            }
            $vars[$k] = $raw
        }
    }
    return $vars
}

function Parse-JsonpChallenge([string] $Raw) {
    $i = $Raw.IndexOf('(')
    $j = $Raw.LastIndexOf(')')
    if ($i -lt 0 -or $j -le $i) { return $null }
    $json = $Raw.Substring($i + 1, $j - $i - 1)
    try {
        $obj = $json | ConvertFrom-Json
    } catch { return $null }
    if (-not $obj.challenge -or -not $obj.client_ip) { return $null }
    return @{ Challenge = [string]$obj.challenge; ClientIp = [string]$obj.client_ip }
}

function Extract-IpFromLoginPage([string] $Html) {
    $patterns = @(
        'id="user_ip"\s+value="([^"]+)"'
        'ip\s*[:=]\s*"([^"]+)"'
        '"user_ip"\s*:\s*"([^"]+)"'
    )
    foreach ($p in $patterns) {
        if ($Html -match $p) { return $Matches[1] }
    }
    return $null
}

function Add32([uint32] $a, [uint32] $b) {
    [uint32](([uint64]$a + $b) -band 0xFFFFFFFF)
}
function Xor32([uint32] $a, [uint32] $b) {
    [uint32](($a -bxor $b) -band 0xFFFFFFFF)
}
function Sl32([uint32] $a, [int] $b) {
    [uint32](([uint64]($a -band 0xFFFFFFFF) -shl $b) -band 0xFFFFFFFF)
}
function Sr32([uint32] $a, [int] $b) {
    [uint32]([uint64]($a -band 0xFFFFFFFF) -shr $b)
}

function Get-SFunc {
    param([string] $Str, [string] $WithLength)
    $chars = $Str.ToCharArray()
    $c = $chars.Length
    $v = New-Object System.Collections.Generic.List[uint32]
    for ($i = 0; $i -lt $c; $i += 4) {
        $ch0 = [int][char]$chars[$i]
        $ch1 = if ($i + 1 -lt $c) { [int][char]$chars[$i + 1] } else { 0 }
        $ch2 = if ($i + 2 -lt $c) { [int][char]$chars[$i + 2] } else { 0 }
        $ch3 = if ($i + 3 -lt $c) { [int][char]$chars[$i + 3] } else { 0 }
        $w = [uint32]($ch0 -bor ($ch1 * 256) -bor ($ch2 * 65536) -bor ($ch3 * 16777216))
        [void]$v.Add($w)
    }
    if ($WithLength -eq '1') { [void]$v.Add([uint32]$c) }
    return , $v.ToArray()
}

function Invoke-XEncode {
    param([string] $Str, [string] $Key)
    if ([string]::IsNullOrEmpty($Str)) { return @() }
    $v = [uint32[]]@(Get-SFunc $Str '1')
    $k = [uint32[]]@(Get-SFunc $Key '0')
    $kList = New-Object System.Collections.Generic.List[uint32]
    foreach ($x in $k) { [void]$kList.Add($x) }
    while ($kList.Count -lt 4) { [void]$kList.Add(0) }
    $k = $kList.ToArray()
    $n = $v.Length - 1
    if ($n -lt 0) { return @() }
    $z = $v[$n]
    $y = $v[0]
    $c = [uint32][int32](-1640531527)
    $d = [uint32]0
    $q = [int][math]::Floor(6 + 52 / ($n + 1))
    for (; $q -gt 0; $q--) {
        $d = Add32 $d $c
        $e = [uint32](($d -shr 2) -band 3)
        for ($p = 0; $p -lt $n; $p++) {
            $y = $v[$p + 1]
            $m = Xor32 (Sr32 $z 5) (Sl32 $y 2)
            $t = Xor32 (Xor32 (Sr32 $y 3) (Sl32 $z 4)) (Xor32 $d $y)
            $m = [uint32](([uint64]$m + $t) -band 0xFFFFFFFF)
            $idx = Xor32 ([uint32]($p -band 3)) $e
            $elem = $k[$idx]
            $t2 = Xor32 $elem $z
            $m = [uint32](([uint64]$m + $t2) -band 0xFFFFFFFF)
            $v[$p] = Add32 $v[$p] $m
            $z = $v[$p]
        }
        $y = $v[0]
        $m = Xor32 (Sr32 $z 5) (Sl32 $y 2)
        $t = Xor32 (Xor32 (Sr32 $y 3) (Sl32 $z 4)) (Xor32 $d $y)
        $m = [uint32](([uint64]$m + $t) -band 0xFFFFFFFF)
        $p = $n
        $idx = Xor32 ([uint32]($p -band 3)) $e
        $elem = $k[$idx]
        $t2 = Xor32 $elem $z
        $m = [uint32](([uint64]$m + $t2) -band 0xFFFFFFFF)
        $v[$n] = Add32 $v[$n] $m
        $z = $v[$n]
    }
    return , $v
}

function Invoke-LFunc {
    param([string] $Str, [string] $Key)
    $a = @(Invoke-XEncode $Str $Key)
    $sb = New-Object System.Text.StringBuilder
    foreach ($word in $a) {
        $w = [uint32]$word
        [void]$sb.Append([char]($w -band 255))
        [void]$sb.Append([char](($w -shr 8) -band 255))
        [void]$sb.Append([char](($w -shr 16) -band 255))
        [void]$sb.Append([char](($w -shr 24) -band 255))
    }
    return $sb.ToString()
}

function Get-HmacMd5Hex([string] $Password, [string] $Challenge) {
    $hmac = New-Object System.Security.Cryptography.HMACMD5
    $hmac.Key = [System.Text.Encoding]::UTF8.GetBytes($Challenge)
    $hash = $hmac.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($Password))
    $hmac.Dispose()
    return ([System.BitConverter]::ToString($hash) -replace '-', '').ToLowerInvariant()
}

function Get-Sha1Hex([string] $Text) {
    $sha1 = [System.Security.Cryptography.SHA1]::Create()
    try {
        $bytes = [System.Text.Encoding]::UTF8.GetBytes($Text)
        $hash = $sha1.ComputeHash($bytes)
        return ([System.BitConverter]::ToString($hash) -replace '-', '').ToLowerInvariant()
    } finally { $sha1.Dispose() }
}

function ConvertTo-SrunB64([string] $Binary) {
    $enc = [System.Text.Encoding]::GetEncoding(28591)
    $bytes = $enc.GetBytes($Binary)
    $b64 = [Convert]::ToBase64String($bytes)
    $from = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/'
    $to = 'LVoJPiCN2R8G90yg+hmFHuacZ1OWMnrsSTXkYpUq/3dlbfKwv6xztjI7DeBE45QA'
    $sb = New-Object System.Text.StringBuilder
    foreach ($ch in $b64.ToCharArray()) {
        $idx = $from.IndexOf($ch)
        if ($idx -ge 0) { [void]$sb.Append($to[$idx]) } else { [void]$sb.Append($ch) }
    }
    return $sb.ToString()
}


# --- CLI: help ---
if ($Command -eq 'help') {
    @'
用法:
  .\Login.ps1 login
  .\Login.ps1 logout
  .\Login.ps1 login -Acid 67
  .\Login.ps1 login 67

配置: 将仓库内 config.example 复制为 windows\config 并填写 USERNAME、PASSWORD、ACID。
环境变量可覆盖: BUAA_USERNAME, BUAA_PASSWORD, BUAA_ACID；调试: $env:BUAA_DEBUG='1'
'@ | Write-Output
    exit 0
}

if (-not (Test-Path -LiteralPath $ConfigPath)) {
    Write-Error "缺少 config。请将 config.example 复制为 windows\config 并填写。"
}

$cfg = Read-BashConfig $ConfigPath

function Cfg([string] $Key, [string] $Default = '') {
    if ($cfg.ContainsKey($Key) -and $null -ne $cfg[$Key]) { return [string]$cfg[$Key] }
    return $Default
}

$USERNAME = if ($env:BUAA_USERNAME) { $env:BUAA_USERNAME } else { Cfg 'USERNAME' }
$PASSWORD = if ($env:BUAA_PASSWORD) { $env:BUAA_PASSWORD } else { Cfg 'PASSWORD' }

$cliAcid = if ($Acid) { $Acid } elseif ($AcidArg) { $AcidArg } else { '' }
$AC_ID = if ($cliAcid) { $cliAcid } elseif ($env:BUAA_ACID) { $env:BUAA_ACID } else { Cfg 'ACID' }

$SRUN_SCHEME = if ($cfg['SRUN_SCHEME']) { $cfg['SRUN_SCHEME'] } else { 'https' }
$SRUN_HOST = if ($cfg['SRUN_HOST']) { $cfg['SRUN_HOST'] } else { 'gw.buaa.edu.cn' }
$SRUN_THEME = if ($cfg['SRUN_THEME']) { $cfg['SRUN_THEME'] } elseif ($cfg['BUAA_THEME']) { $cfg['BUAA_THEME'] } else { 'buaa' }
$SRUN_REF_URL = if ($cfg['SRUN_REF_URL']) { $cfg['SRUN_REF_URL'] } else { 'www.buaa.edu.cn' }
$SRUN_DOMAIN = Cfg 'SRUN_DOMAIN'

$SRUN_LOGIN_PAGE_URL = if ($cfg['SRUN_LOGIN_PAGE_URL']) { $cfg['SRUN_LOGIN_PAGE_URL'] } else { "${SRUN_SCHEME}://${SRUN_HOST}/index_1.html?ad_check=1" }
$SRUN_PORTAL_PC_BASE_URL = if ($cfg['SRUN_PORTAL_PC_BASE_URL']) { $cfg['SRUN_PORTAL_PC_BASE_URL'] } else { "${SRUN_SCHEME}://${SRUN_HOST}/srun_portal_pc" }
$SRUN_GET_CHALLENGE_URL = if ($cfg['SRUN_GET_CHALLENGE_URL']) { $cfg['SRUN_GET_CHALLENGE_URL'] } else { "${SRUN_SCHEME}://${SRUN_HOST}/cgi-bin/get_challenge" }
$SRUN_PORTAL_API_URL = if ($cfg['SRUN_PORTAL_API_URL']) { $cfg['SRUN_PORTAL_API_URL'] } else { "${SRUN_SCHEME}://${SRUN_HOST}/cgi-bin/srun_portal" }

if ($SRUN_PORTAL_API_URL -match '^[a-zA-Z]+://([^/]+)') {
    $SRUN_HOST_HEADER = if ($cfg['SRUN_HOST_HEADER']) { $cfg['SRUN_HOST_HEADER'] } else { $Matches[1] }
} else {
    $SRUN_HOST_HEADER = if ($cfg['SRUN_HOST_HEADER']) { $cfg['SRUN_HOST_HEADER'] } else { $SRUN_HOST }
}

if ($cliAcid) { $AC_ID_SOURCE = '命令行参数' }
elseif ($env:BUAA_ACID) { $AC_ID_SOURCE = '环境变量 BUAA_ACID' }
else { $AC_ID_SOURCE = 'config 的 ACID' }

if ([string]::IsNullOrWhiteSpace($USERNAME)) {
    Write-Error '缺少 USERNAME，请在 config 中填写。'
}
if ($Command -eq 'login' -and [string]::IsNullOrWhiteSpace($PASSWORD)) {
    Write-Error '登录需要 PASSWORD，请在 config 中填写。'
}
if ([string]::IsNullOrWhiteSpace($AC_ID)) {
    Write-Error '缺少 ACID，请在浏览器门户 URL 中查看 ac_id 并写入 config。'
}

$SYSNAME = 'Windows+10'
$UA = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36'
$cookieFile = Join-Path $env:TEMP ("srun_cookie_{0}.txt" -f [Guid]::NewGuid().ToString('N'))

try {
    $curlBase = @(
        '-k', '-s', '--noproxy', '*'
        '-H', "Host: $SRUN_HOST_HEADER"
        '-H', 'User-Agent: ' + $UA
    )

    $pageArgs = $curlBase + @(
        '-c', $cookieFile
        '-H', 'Upgrade-Insecure-Requests: 1'
        '-H', 'Sec-Fetch-Mode: navigate'
        '-H', 'Sec-Fetch-User: ?1'
        '-H', 'DNT: 1'
        '-H', 'Accept: text/html,application/xhtml+xml,application/xml;q=0.9,image/webp,*/*;q=0.8'
        '-H', 'Purpose: prefetch'
        '-H', 'Sec-Fetch-Site: none'
        '-H', 'Accept-Language: en-US,en;q=0.9,zh-CN;q=0.8,zh;q=0.7'
        '-H', "Cookie: pgv_pvi=2381688832; AD_VALUE=8751256e; cookie=0; lang=zh-CN; user=$USERNAME"
        $SRUN_LOGIN_PAGE_URL
    )
    $RESULT = & curl.exe @pageArgs 2>$null

    if ($env:BUAA_DEBUG) {
        Write-Host '=== DEBUG: index 响应前 800 字符 ===' -ForegroundColor DarkGray
        $snippet = if ($RESULT.Length -gt 800) { $RESULT.Substring(0, 800) } else { $RESULT }
        Write-Host $snippet -ForegroundColor DarkGray
    }

    Write-Host "AC_ID: $AC_ID (来自 $AC_ID_SOURCE)"

    $refPortalPc = "${SRUN_PORTAL_PC_BASE_URL}?ac_id=${AC_ID}&theme=${SRUN_THEME}&url=${SRUN_REF_URL}&srun_domain=${SRUN_DOMAIN}"

    $loginPageIp = Extract-IpFromLoginPage $RESULT
    $ipaddrCfg = Cfg 'IPADDR'
    $CHALLENGE_IP = if ($ipaddrCfg) { $ipaddrCfg } elseif ($loginPageIp) { $loginPageIp } else { '0.0.0.0' }

    $TIMESTAMP = [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()

    $gcUrl = "${SRUN_GET_CHALLENGE_URL}?callback=jQuery112407419864172676014_1566720734115&username=$USERNAME&ip=$CHALLENGE_IP&_=$TIMESTAMP"
    $challengeArgs = $curlBase + @(
        '-b', $cookieFile
        '-H', 'Accept: text/javascript, application/javascript, application/ecmascript, application/x-ecmascript, */*; q=0.01'
        '-H', 'DNT: 1'
        '-H', 'X-Requested-With: XMLHttpRequest'
        '-H', 'User-Agent: ' + $UA
        '-H', 'Sec-Fetch-Mode: cors'
        '-H', 'Sec-Fetch-Site: same-origin'
        '-H', "Referer: $refPortalPc"
        '-H', 'Accept-Language: en-US,en;q=0.9,zh-CN;q=0.8,zh;q=0.7'
        $gcUrl
    )
    $RESULT = & curl.exe @challengeArgs 2>$null

    if ($env:BUAA_DEBUG) {
        Write-Host '=== DEBUG: get_challenge 响应 ===' -ForegroundColor DarkGray
        Write-Host $RESULT -ForegroundColor DarkGray
    }

    $parsed = Parse-JsonpChallenge $RESULT
    if (-not $parsed) {
        Write-Error "无法解析 get_challenge。响应: $RESULT"
    }
    $CHALLENGE = $parsed.Challenge
    $CLIENTIP = $parsed.ClientIp
    Write-Host "Challenge: $CHALLENGE"
    Write-Host "Client IP: $CLIENTIP"

    if ($Command -eq 'login') {
        $EncPwd = Get-HmacMd5Hex $PASSWORD $CHALLENGE
        Write-Host "Encrypted PWD: $EncPwd"

        $INFO = "{`"username`":`"$USERNAME`",`"password`":`"$PASSWORD`",`"ip`":`"$CLIENTIP`",`"acid`":`"$AC_ID`",`"enc_ver`":`"srun_bx1`"}"
        $encBin = Invoke-LFunc $INFO $CHALLENGE
        $ENCRYPT_INFO = ConvertTo-SrunB64 $encBin
        Write-Host "Encrypted Info: $ENCRYPT_INFO"

        $CHKSTR = "${CHALLENGE}${USERNAME}${CHALLENGE}${EncPwd}${CHALLENGE}${AC_ID}${CHALLENGE}${CLIENTIP}${CHALLENGE}200${CHALLENGE}1${CHALLENGE}{SRBX1}${ENCRYPT_INFO}"
        $CHKSUM = Get-Sha1Hex $CHKSTR
        Write-Host "Checksum: $CHKSUM"

        $URL_INFO = $ENCRYPT_INFO -replace '/', '%2F' -replace '=', '%3D' -replace '\+', '%2B'
        $DS_STACK = if ($env:BUAA_DOUBLE_STACK) { $env:BUAA_DOUBLE_STACK } else { '0' }

        $loginUrl = "${SRUN_PORTAL_API_URL}?callback=jQuery112407419864172676014_1566720734115&action=login&username=$USERNAME&password=%7BMD5%7D$EncPwd&ac_id=$AC_ID&ip=$CLIENTIP&chksum=$CHKSUM&info=%7BSRBX1%7D$URL_INFO&n=200&type=1&os=$SYSNAME&name=Windows&double_stack=$DS_STACK&_=$TIMESTAMP"
        $loginArgs = $curlBase + @(
            '-b', $cookieFile
            '-H', 'Accept: text/javascript, application/javascript, application/ecmascript, application/x-ecmascript, */*; q=0.01'
            '-H', 'DNT: 1'
            '-H', 'X-Requested-With: XMLHttpRequest'
            '-H', 'User-Agent: ' + $UA
            '-H', 'Sec-Fetch-Mode: cors'
            '-H', 'Sec-Fetch-Site: same-origin'
            '-H', "Referer: $refPortalPc"
            '-H', 'Accept-Language: en-US,en;q=0.9,zh-CN;q=0.8,zh;q=0.7'
            $loginUrl
        )
        $LOGIN_OUT = & curl.exe @loginArgs 2>$null
        Write-Host "srun_portal(login): $LOGIN_OUT"
        if ($env:BUAA_DEBUG) {
            Write-Host "=== DEBUG: ac_id=$AC_ID ip=$CLIENTIP double_stack=$DS_STACK host=$SRUN_HOST_HEADER" -ForegroundColor DarkGray
        }
    }
    elseif ($Command -eq 'logout') {
        $logoutUrl = "${SRUN_PORTAL_API_URL}?callback=jQuery112407419864172676014_1566720734115&action=logout&username=$USERNAME&ac_id=$AC_ID&ip=$CLIENTIP"
        $logoutArgs = $curlBase + @(
            '-b', $cookieFile
            '-H', 'Accept: text/javascript, application/javascript, application/ecmascript, application/x-ecmascript, */*; q=0.01'
            '-H', 'DNT: 1'
            '-H', 'X-Requested-With: XMLHttpRequest'
            '-H', 'User-Agent: ' + $UA
            '-H', 'Sec-Fetch-Mode: cors'
            '-H', 'Sec-Fetch-Site: same-origin'
            '-H', "Referer: $refPortalPc"
            '-H', 'Accept-Language: en-US,en;q=0.9,zh-CN;q=0.8,zh;q=0.7'
            $logoutUrl
        )
        $LOGOUT_OUT = & curl.exe @logoutArgs 2>$null
        Write-Host "srun_portal(logout): $LOGOUT_OUT"
    }
}
finally {
    if (Test-Path -LiteralPath $cookieFile) { Remove-Item -LiteralPath $cookieFile -Force -ErrorAction SilentlyContinue }
}

exit 0
