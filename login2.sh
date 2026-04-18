#!/bin/bash
# 依赖: curl、openssl、python3
#
# 配置: 同目录 config 文件，含 USERNAME、PASSWORD。（ACID 默认自动获取，失败时回退 config）
# 可选环境变量: BUAA_USERNAME / BUAA_PASSWORD / BUAA_ACID

#####################
# Login Information #
#####################
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
option="login"
CLI_ACID=""

if [[ $# -gt 0 ]]; then
    case "$1" in
        login|logout)
            option="$1"
            shift
            ;;
        help|-h|--help)
            option="help"
            ;;
        *)
            echo "未知命令: $1" >&2
            echo "可用命令: login / logout / help" >&2
            exit 1
            ;;
    esac
fi

while [[ $# -gt 0 ]]; do
    case "$1" in
        --acid|-a)
            CLI_ACID="$2"
            shift 2
            ;;
        --acid=*)
            CLI_ACID="${1#*=}"
            shift
            ;;
        *)
            if [[ -z "$CLI_ACID" ]]; then
                CLI_ACID="$1"
                shift
            else
                echo "未知参数: $1" >&2
                exit 1
            fi
            ;;
    esac
done

if [[ "$option" == "help" ]]; then
    cat <<'EOF'
用法:
  bash login.sh login    # 登录 (自动获取 ACID)
  bash login.sh logout   # 注销
EOF
    exit 0
fi

if [[ ! -f "$SCRIPT_DIR/config" ]]; then
    echo "缺少 config 文件。请创建并填写 USERNAME 和 PASSWORD。" >&2
    exit 1
fi
# shellcheck source=/dev/null
source "$SCRIPT_DIR/config"

USERNAME="${BUAA_USERNAME:-$USERNAME}"
PASSWORD="${BUAA_PASSWORD:-$PASSWORD}"

# SRun 连接参数
SRUN_SCHEME="${SRUN_SCHEME:-https}"
SRUN_HOST="${SRUN_HOST:-gw.buaa.edu.cn}"
SRUN_THEME="${SRUN_THEME:-${BUAA_THEME:-buaa}}"
SRUN_REF_URL="${SRUN_REF_URL:-www.buaa.edu.cn}"
SRUN_DOMAIN="${SRUN_DOMAIN:-}"

SRUN_LOGIN_PAGE_URL="${SRUN_LOGIN_PAGE_URL:-${SRUN_SCHEME}://${SRUN_HOST}/index_1.html?ad_check=1}"
SRUN_PORTAL_PC_BASE_URL="${SRUN_PORTAL_PC_BASE_URL:-${SRUN_SCHEME}://${SRUN_HOST}/srun_portal_pc}"
SRUN_GET_CHALLENGE_URL="${SRUN_GET_CHALLENGE_URL:-${SRUN_SCHEME}://${SRUN_HOST}/cgi-bin/get_challenge}"
SRUN_PORTAL_API_URL="${SRUN_PORTAL_API_URL:-${SRUN_SCHEME}://${SRUN_HOST}/cgi-bin/srun_portal}"

if [[ "$SRUN_PORTAL_API_URL" =~ ^[a-zA-Z]+://([^/]+) ]]; then
    SRUN_HOST_HEADER="${SRUN_HOST_HEADER:-${BASH_REMATCH[1]}}"
else
    SRUN_HOST_HEADER="${SRUN_HOST_HEADER:-$SRUN_HOST}"
fi

#################
# Customization #
#################
SYSNAME="Mac+OS"
UA="Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36"
COOKIEFILE=$(mktemp)

# ==========================================
# 自动获取 AC_ID (使用 Python 确保正则提取万无一失)
# ==========================================
if [[ -n "$CLI_ACID" ]]; then
    AC_ID="$CLI_ACID"
    AC_ID_SOURCE="命令行参数"
elif [[ -n "${BUAA_ACID:-}" ]]; then
    AC_ID="$BUAA_ACID"
    AC_ID_SOURCE="环境变量 BUAA_ACID"
else
    # 直接抓取并使用 Python 正则精准提取数字
    AC_ID=$(curl -sL -A "$UA" "${SRUN_SCHEME}://${SRUN_HOST}" | python3 -c '
import sys, re
m = re.search(r"ac_id[^0-9]+([0-9]+)", sys.stdin.read())
if m: print(m.group(1))
')

    if [[ -n "${AC_ID:-}" ]]; then
        AC_ID_SOURCE="自动网页抓取"
    elif [[ -n "${ACID:-}" ]]; then
        AC_ID="$ACID"
        AC_ID_SOURCE="config 的 ACID（自动抓取失败回退）"
    else
        AC_ID_SOURCE="自动网页抓取失败"
    fi
fi

if [[ -z "${USERNAME:-}" || ( "$option" == "login" && -z "${PASSWORD:-}" ) ]]; then
    echo "缺少学号 USERNAME 或 密码 PASSWORD。请在 config 中填写。" >&2
    exit 1
fi
if [[ -z "${AC_ID:-}" ]]; then
    echo "获取 ACID 失败，且 config 中未提供 ACID。请检查网络，或在 config 中填写 ACID。" >&2
    exit 1
fi

#################################
# 纯 Python 解析模块 (抛弃 cut) #
#################################

jsonp_parse_challenge() {
    echo "$1" | python3 -c '
import sys, json
raw = sys.stdin.read()
i, j = raw.find("("), raw.rfind(")")
if i < 0 or j <= i:
    sys.exit(1)
obj = json.loads(raw[i + 1 : j])
ch, ip = obj.get("challenge"), obj.get("client_ip")
if not ch or not ip:
    sys.exit(1)
print(ch + "\t" + ip)
' 2>/dev/null
}

extract_ip_from_login_page() {
    echo "$1" | python3 -c '
import re, sys
raw = sys.stdin.read()
patterns = [
    r"id=\"user_ip\"\s+value=\"([^\"]+)\"",
    r"ip\s*[:=]\s*\"([^\"]+)\"",
    r"\"user_ip\"\s*:\s*\"([^\"]+)\"",
]
for p in patterns:
    m = re.search(p, raw)
    if m:
        print(m.group(1))
        break
' 2>/dev/null
}

# 毫秒时间戳
TIMESTAMP=$(python3 -c 'import time; print(int(time.time()*1000))')

#################################
# Utility Functions & Variables #
#################################

function str2ascii() {
    s=$1
    if [ "$s" == '\"' ]; then
        ascii="34"
    else
        ascii=$(printf "%d" "'$s")
    fi
    return $((ascii))
}

function ascii2str() {
    code=$1
    printf '\\x%x' $code
}

function floor() {
    result=$(echo $1 | cut -f1 -d".")
    return $((result))
}

function sl() {
    a=$1; b=$2
    result=$((a<<b))
    if [ "$result" -gt "2147483647" ]; then
        result=$((result&4294967295|18446744069414584320))
    fi
    echo $result
}

function sr() {
    a=$1; b=$2
    result=$(((a&4294967295)>>b))
    echo $result
}

function xor() {
    a=$1; b=$2
    result=$(((a^b)&4294967295))
    if [ "$result" -gt "2147483647" ]; then
        result=$((result|18446744069414584320))
    fi
    echo $result
}

function add() {
    a=$1; b=$2
    result=$(((a+b)&4294967295))
    if [ "$result" -gt "2147483647" ]; then
        result=$((result|18446744069414584320))
    fi
    echo $result
}

######################
# srun_bx1 Algorithm #
######################

function s_func() {
    a=$1; b=$2
    c=${#a}; v=()
    aa=($(echo $a | grep -o .))
    for ((i=0;i<c;i+=4)); do
        idx=$((i>>2))
        str2ascii ${aa[i]}; item1=$?
        str2ascii ${aa[((i+1))]}; item2=$(($? * 256))
        str2ascii ${aa[((i+2))]}; item3=$(($? * 65536))
        str2ascii ${aa[((i+3))]}; item4=$(($? * 16777216))
        v[idx]=$((item1|item2|item3|item4))
    done
    if [ "$b" == "1" ]; then v[${#v[@]}]=$c; fi
    v=$( IFS=" "; echo "${v[*]}" )
    echo $v
}

function xEncode() {
    str=$1; key=$2
    if [ "$str" == "" ]; then return; fi
    v=$(s_func "$str" "1"); k=$(s_func "$key" "0")
    v=($v); k=($k)

    while [ ${#k[@]} -lt 4 ]; do k[${#k[@]}]=0; done
    n=$((${#v[@]}-1)); z=${v[$n]}; y=${v[0]}
    c=-1640531527; m=0; e=0; p=0
    floor $((6+52/(n+1))); q=$?; d=0
    
    for ((;q>0;q-=1)); do
        d=$(add $d $c); e=$((d>>2&3))
        for ((p=0;p<n;p+=1)); do
            y=${v[$((p+1))]}
            t1=$(sr $z 5); t2=$(sl $y 2); m=$(xor $t1 $t2)
            t1=$(sr $y 3); t2=$(sl $z 4); t1=$(xor $t1 $t2); t2=$(xor $d $y); t=$(xor $t1 $t2); m=$((m+t))
            t1=$((p&3)); idx=$(xor $t1 $e); elem=${k[$idx]}; t2=$(xor $elem $z); m=$((m+t2))
            v[$p]=$(add ${v[$p]} $m); z=${v[$p]}
        done
        y=${v[0]}
        t1=$(sr $z 5); t2=$(sl $y 2); m=$(xor $t1 $t2)
        t1=$(sr $y 3); t2=$(sl $z 4); t1=$(xor $t1 $t2); t2=$(xor $d $y); t=$(xor $t1 $t2); m=$((m+t))
        t1=$((p&3)); idx=$(xor $t1 $e); elem=${k[$idx]}; t2=$(xor $elem $z); m=$((m+t2))
        v[$n]=$(add ${v[$n]} $m); z=${v[$n]}
    done
    v=$( IFS=" "; echo "${v[*]}" )
    echo $v
}

function l_func() {
    str=$1; key=$2
    a=$(xEncode "$str" "$key")
    a=($a); d=${#a[@]}; c=$(((d-1)<<2))
    for ((i=0;i<d;i+=1)); do
        code1=$((${a[$i]}&255)); s1=$(ascii2str $code1)
        code2=$((${a[$i]}>>8&255)); s2=$(ascii2str $code2)
        code3=$((${a[$i]}>>16&255)); s3=$(ascii2str $code3)
        code4=$((${a[$i]}>>24&255)); s4=$(ascii2str $code4)
        a[$i]=${s1}${s2}${s3}${s4}
    done
    result=$( IFS=""; echo "${a[*]}" )
    echo $result 
}

################
# Main Process #
################

RESULT=$(curl -k -s -c "$COOKIEFILE" \
--noproxy '*' \
-H "Host: $SRUN_HOST_HEADER" \
-H 'Upgrade-Insecure-Requests: 1' \
-H "User-Agent: $UA" \
-H 'Sec-Fetch-Mode: navigate' \
-H 'Sec-Fetch-User: ?1' \
-H 'DNT: 1' \
-H "Cookie: pgv_pvi=2381688832; AD_VALUE=8751256e; cookie=0; lang=zh-CN; user=$USERNAME" \
"$SRUN_LOGIN_PAGE_URL")

echo "AC_ID: $AC_ID (来自 $AC_ID_SOURCE)"

REF_PORTAL_PC="${SRUN_PORTAL_PC_BASE_URL}?ac_id=${AC_ID}&theme=${SRUN_THEME}&url=${SRUN_REF_URL}&srun_domain=${SRUN_DOMAIN}"

LOGIN_PAGE_IP="$(extract_ip_from_login_page "$RESULT")"
CHALLENGE_IP="${IPADDR:-${LOGIN_PAGE_IP:-0.0.0.0}}"

# Get challenge number
RESULT=$(curl -k -s -b "$COOKIEFILE" \
--noproxy '*' \
-H "Host: $SRUN_HOST_HEADER" \
-H "X-Requested-With: XMLHttpRequest" \
-H "User-Agent: $UA" \
-H "Referer: $REF_PORTAL_PC" \
"${SRUN_GET_CHALLENGE_URL}?callback=jQuery112407419864172676014_1566720734115&username=${USERNAME}&ip=${CHALLENGE_IP}&_=${TIMESTAMP}")

parsed="$(jsonp_parse_challenge "$RESULT")"
if [[ -z "$parsed" ]]; then
    echo "无法解析 get_challenge，获取 Token 失败。原始响应：" >&2
    echo "$RESULT" >&2
    rm -f "$COOKIEFILE"
    exit 1
fi
IFS=$'\t' read -r CHALLENGE CLIENTIP <<< "$parsed"

echo "Challenge: $CHALLENGE"
echo "Client IP: $CLIENTIP"

if [[ "$option" == "login" ]]; then
    ENCRYPT_PWD=$(echo -n "$PASSWORD" | openssl md5 -hmac "$CHALLENGE")
    ENCRYPT_PWD=${ENCRYPT_PWD#*= }
    PWD=$ENCRYPT_PWD

    INFO='{"username":"'"$USERNAME"'","password":"'"$PASSWORD"'","ip":"'"$CLIENTIP"'","acid":"'"$AC_ID"'","enc_ver":"srun_bx1"}'
    ENCRYPT_INFO=$(l_func "$INFO" "$CHALLENGE")
    ENCRYPT_INFO=$(echo -ne "$ENCRYPT_INFO" | openssl enc -base64 -A | tr "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/" "LVoJPiCN2R8G90yg+hmFHuacZ1OWMnrsSTXkYpUq/3dlbfKwv6xztjI7DeBE45QA")

    CHKSTR="${CHALLENGE}${USERNAME}${CHALLENGE}${ENCRYPT_PWD}${CHALLENGE}${AC_ID}${CHALLENGE}${CLIENTIP}${CHALLENGE}200${CHALLENGE}1${CHALLENGE}{SRBX1}${ENCRYPT_INFO}"
    CHKSUM=$(echo -n "$CHKSTR" | openssl dgst -sha1)
    CHKSUM=${CHKSUM#*= }

    URL_INFO=$(echo -n "$ENCRYPT_INFO" | sed "s/\//%2F/g" | sed "s/=/%3D/g" | sed "s/+/%2B/g")
    DS_STACK="${BUAA_DOUBLE_STACK:-0}"

    LOGIN_OUT=$(curl -k -s -b "$COOKIEFILE" \
        --noproxy '*' \
    -H "Host: $SRUN_HOST_HEADER" \
    -H "X-Requested-With: XMLHttpRequest" \
    -H "User-Agent: $UA" \
    -H "Referer: $REF_PORTAL_PC" \
    "${SRUN_PORTAL_API_URL}?callback=jQuery112407419864172676014_1566720734115&action=login&username=${USERNAME}&password=%7BMD5%7D${PWD}&ac_id=${AC_ID}&ip=${CLIENTIP}&chksum=${CHKSUM}&info=%7BSRBX1%7D${URL_INFO}&n=200&type=1&os=${SYSNAME}&name=Macintosh&double_stack=${DS_STACK}&_=${TIMESTAMP}")
    
    echo "登录请求已发送: $LOGIN_OUT"

elif [[ "$option" == "logout" ]]; then
    LOGOUT_OUT=$(curl -k -s -b "$COOKIEFILE" \
        --noproxy '*' \
    -H "Host: $SRUN_HOST_HEADER" \
    -H "X-Requested-With: XMLHttpRequest" \
    -H "User-Agent: $UA" \
    -H "Referer: $REF_PORTAL_PC" \
    "${SRUN_PORTAL_API_URL}?callback=jQuery112407419864172676014_1566720734115&action=logout&username=${USERNAME}&ac_id=${AC_ID}&ip=${CLIENTIP}")
    
    echo "注销请求已发送: $LOGOUT_OUT"
fi

rm -f "$COOKIEFILE"