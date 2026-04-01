# 供 Login.ps1 / Try-Connect.ps1 / Protect-Connect.ps1 点源；勿单独直接运行。

function Read-SrunBashConfig {
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

<#
 与 login.sh 中 ACID 参数解析一致：按顺序处理，后者覆盖前者；仅在没有已选 ACID 时接受裸位置参数。
#>
function Parse-SrunAcidTailArgs {
    param([string[]] $Args)
    $cliAcid = ''
    $i = 0
    $arr = @($Args | Where-Object { $_ -ne $null -and $_ -ne '' })
    while ($i -lt $arr.Count) {
        $t = [string]$arr[$i]
        switch -Regex ($t) {
            '^--acid$' {
                if ($i + 1 -ge $arr.Count) { throw '参数错误: --acid 需要一个值' }
                $cliAcid = [string]$arr[$i + 1]
                $i += 2
                continue
            }
            '^--acid=' {
                $cliAcid = $t.Substring(7)
                $i++
                continue
            }
            '^-a$' {
                if ($i + 1 -ge $arr.Count) { throw '参数错误: -a 需要一个值' }
                $cliAcid = [string]$arr[$i + 1]
                $i += 2
                continue
            }
            default {
                if (-not $cliAcid) {
                    $cliAcid = $t
                    $i++
                    continue
                }
                throw "未知参数: $t"
            }
        }
    }
    return $cliAcid
}
