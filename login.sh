#!/bin/bash
# 依赖: curl、openssl、python3（用于解析 get_challenge 的 JSONP）
#
# 配置: 同目录 config 文件（见 config.example），含 USERNAME、PASSWORD、ACID。
# 可选环境变量: BUAA_USERNAME / BUAA_PASSWORD / BUAA_ACID（覆盖 config 同名字段）
# BUAA_DEBUG=1、BUAA_DOUBLE_STACK、IPADDR 等见 README

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
		--acid)
			if [[ -z "${2:-}" ]]; then
				echo "参数错误: --acid 需要一个值" >&2
				exit 1
			fi
			CLI_ACID="$2"
			shift 2
			;;
		--acid=*)
			CLI_ACID="${1#*=}"
			shift
			;;
		-a)
			if [[ -z "${2:-}" ]]; then
				echo "参数错误: -a 需要一个值" >&2
				exit 1
			fi
			CLI_ACID="$2"
			shift 2
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
  bash login.sh login    # 登录
  bash login.sh logout   # 注销
	bash login.sh login --acid 67   # 临时指定 ACID
	bash login.sh login 67          # 临时指定 ACID（位置参数）

请使用 bash 运行（不要用 sh）。调试: BUAA_DEBUG=1 bash login.sh login

如何确认 ACID: 用浏览器完成一次校园网登录，看地址栏或 Network 里
  srun_portal_pc?ac_id=数字 —— 将该数字填入 config 的 ACID。
EOF
	exit 0
fi

if [[ ! -f "$SCRIPT_DIR/config" ]]; then
	echo "缺少 config 文件。请复制 config.example 为 config 并填写学号、密码、ACID。" >&2
	exit 1
fi
# shellcheck source=/dev/null
source "$SCRIPT_DIR/config"

USERNAME="${BUAA_USERNAME:-$USERNAME}"
PASSWORD="${BUAA_PASSWORD:-$PASSWORD}"
AC_ID="${CLI_ACID:-${BUAA_ACID:-${ACID:-}}}"

# SRun 连接参数（可在 config 里覆盖）
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

if [[ -n "$CLI_ACID" ]]; then
	AC_ID_SOURCE="命令行参数"
elif [[ -n "${BUAA_ACID:-}" ]]; then
	AC_ID_SOURCE="环境变量 BUAA_ACID"
else
	AC_ID_SOURCE="config 的 ACID"
fi

if [[ -z "${USERNAME:-}" ]]; then
	echo "缺少学号 USERNAME。请在 config 中填写。" >&2
	exit 1
fi
if [[ "$option" == "login" && -z "${PASSWORD:-}" ]]; then
	echo "登录需要密码 PASSWORD。请在 config 中填写。" >&2
	exit 1
fi
if [[ -z "${AC_ID:-}" ]]; then
	echo "缺少 ACID（门户 ac_id）。请在浏览器登录后查看地址栏 ac_id= 并写入 config，见 README。" >&2
	exit 1
fi

#################
# Customization #
#################
# If you need to modify SYSNAME, please use a url-encoded string
SYSNAME="Mac+OS"
UA="Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36"
COOKIEFILE=`mktemp`

# 从 JSONP 文本解析 challenge、client_ip（避免 cut 字段错位导致假登录）
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

# 从登录页文本尽量提取 IP（兼容不同 SRun 页面）
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

#################################
# Utility Functions & Variables #
#################################

# TIMESTAMP: ms（macOS 自带 date 不支持 %3N，用 python3 兜底）
if command -v python3 >/dev/null 2>&1; then
	TIMESTAMP=$(python3 -c 'import time; print(int(time.time()*1000))')
else
	TIMESTAMP="$(date +%s)000"
fi

# str2ascii(str): Convert a character to integer.
function str2ascii()
{
	s=$1
	if [ "$s" == '\"' ]; then
		ascii="34"
	else
		ascii=`printf "%d" "'$s"`
	fi
	return $((ascii))
}

# ascii2str(code): Convert a integer to hex digit code.
function ascii2str()
{
	code=$1
	printf '\\x%x' $code
}

# floor(num): Dirty implementation of Math.floor().
function floor()
{
	result=`echo $1 | cut -f1 -d"."`
	return $((result))
}

# Note that integer in bash in mostly 64 bits, 
# functions below aim to simulate 32 bits calculation.

# sl(base, shift): Bitwise shift left (32 bits).
function sl()
{
	a=$1
	b=$2
	result=$((a<<b))
	if [ "$result" -gt "2147483647" ]; then
		result=$((result&4294967295|18446744069414584320))
	fi
	echo $result
}

# sr(base, shift): Bitwise shift right logical (32 bits).
function sr()
{
	a=$1
	b=$2
	result=$(((a&4294967295)>>b))
	echo $result
}

# xor(num1, num2): Bitwise xor (32 bits).
function xor()
{
	a=$1
	b=$2
	result=$(((a^b)&4294967295))
	if [ "$result" -gt "2147483647" ]; then
		result=$((result|18446744069414584320))
	fi
	echo $result
}

# add(num1, num2): Bitwise add (32 bits).
function add()
{
	a=$1
	b=$2
	result=$(((a+b)&4294967295))
	if [ "$result" -gt "2147483647" ]; then
		result=$((result|18446744069414584320))
	fi
	echo $result
}

######################
# srun_bx1 Algorithm #
######################

# s_func(a, b): reimplement of s()
function s_func()
{
	a=$1
	b=$2
	c=${#a}
	v=()
	aa=(`echo $a | grep -o .`)
	for ((i=0;i<c;i+=4)); do
		idx=$((i>>2))
		str2ascii ${aa[i]}
		item1=$?
		str2ascii ${aa[((i+1))]}
		item2=$?
		item2=$((item2*256))
		str2ascii ${aa[((i+2))]}
		item3=$?
		item3=$((item3*65536))
		str2ascii ${aa[((i+3))]}
		item4=$?
		item4=$((item4*16777216))
		v[idx]=$((item1|item2|item3|item4))
		#echo "v["$idx"]="$((item1|item2|item3|item4))
	done
	if [ "$b" == "1" ]; then
		v[${#v[@]}]=$c
	fi
	v=$( IFS=" "; echo "${v[*]}" )
	echo $v
}

# xEncode(str, challenge): reimplement of xEncode()
function xEncode()
{
	str=$1
	key=$2
	if [ $str == "" ]; then
		return ""
	fi
	v=$(s_func $str "1")
	k=$(s_func $key "0")
	v=($v)
	k=($k)
	#echo ${v[@]} > v.txt
	#echo ${k[@]} > k.txt

	while [ ${#k[@]} -lt 4 ]; do
		k[${#k[@]}]=0
	done
	n=$((${#v[@]}-1))
	z=${v[$n]}
	y=${v[0]}
	c=-1640531527
	m=0
	e=0
	p=0
	floor $((6+52/(n+1)))
	q=$?
	d=0
	for ((;q>0;q-=1)); do
		d=$(add $d $c)
		e=$((d>>2&3))
		for ((p=0;p<n;p+=1)); do
			y=${v[$((p+1))]}
			#echo "y= "$y
			t1=$(sr $z 5)
			t2=$(sl $y 2)
			m=$(xor $t1 $t2)
			#echo "m1= "$m
			t1=$(sr $y 3)
			t2=$(sl $z 4)
			t1=$(xor $t1 $t2)
			t2=$(xor $d $y)
			t=$(xor $t1 $t2)
			m=$((m+t))
			#echo "m2= "$m
			t1=$((p&3))
			idx=$(xor $t1 $e)
			elem=${k[$idx]}
			t2=$(xor $elem $z)
			m=$((m+t2))
			#echo "m3= "$m
			v[$p]=$(add ${v[$p]} $m)
			z=${v[$p]}
			#echo "z= "$z
		done
		y=${v[0]}
		#echo "y= "$y
		t1=$(sr $z 5)
		t2=$(sl $y 2)
		m=$(xor $t1 $t2)
		#echo "m1= "$m
		t1=$(sr $y 3)
		t2=$(sl $z 4)
		t1=$(xor $t1 $t2)
		t2=$(xor $d $y)
		t=$(xor $t1 $t2)
		m=$((m+t))
		#echo "m2= "$m
		t1=$((p&3))
		idx=$(xor $t1 $e)
		elem=${k[$idx]}
		t2=$(xor $elem $z)
		m=$((m+t2))
		#echo "m3= "$m
		v[$n]=$(add ${v[$n]} $m)
		z=${v[$n]}
		#echo "z= "$z
	done
	#echo ${v[@]}
	v=$( IFS=" "; echo "${v[*]}" )
	echo $v
}

# l_func(str, key): reimplement of l(), but not exactly the same.
function l_func()
{
	str=$1
	key=$2
	a=$(xEncode $str $key)
	#echo ${a[@]} > x.txt
	a=($a)
	d=${#a[@]}
	c=$(((d-1)<<2))
	for ((i=0;i<d;i+=1)); do
		code1=$((${a[$i]}&255))
		s1=$(ascii2str $code1)
		code2=$((${a[$i]}>>8&255))
		s2=$(ascii2str $code2)
		code3=$((${a[$i]}>>16&255))
		s3=$(ascii2str $code3)
		code4=$((${a[$i]}>>24&255))
		s4=$(ascii2str $code4)
		a[$i]=${s1}${s2}${s3}${s4}
	done
	result=$( IFS=""; echo "${a[*]}" )
	echo $result 
}

################
# Main Process #
################

# Cookies: $COOKIEFILE；AC_ID 来自 config 的 ACID
RESULT=`curl -k -s -c $COOKIEFILE \
--noproxy '*' \
-H "Host: $SRUN_HOST_HEADER" \
-H 'Upgrade-Insecure-Requests: 1' \
-H 'User-Agent: $UA' \
-H 'Sec-Fetch-Mode: navigate' \
-H 'Sec-Fetch-User: ?1' \
-H 'DNT: 1' \
-H 'Accept: text/html,application/xhtml+xml,application/xml;q=0.9,image/webp,image/apng,*/*;q=0.8,application/signed-exchange;v=b3' \
-H 'Purpose: prefetch' \
-H 'Sec-Fetch-Site: none' \
-H 'Accept-Language: en-US,en;q=0.9,zh-CN;q=0.8,zh;q=0.7,zh-TW;q=0.6' \
-H 'Cookie: pgv_pvi=2381688832; AD_VALUE=8751256e; cookie=0; lang=zh-CN; user=$USERNAME' \
"$SRUN_LOGIN_PAGE_URL"`

if [[ -n "${BUAA_DEBUG:-}" ]]; then
	echo "=== DEBUG: index_1.html 响应片段（前 800 字符）===" >&2
	echo "$RESULT" | head -c 800 >&2
	echo >&2
fi

echo "AC_ID: $AC_ID (来自 $AC_ID_SOURCE)"

REF_PORTAL_PC="${SRUN_PORTAL_PC_BASE_URL}?ac_id=${AC_ID}&theme=${SRUN_THEME}&url=${SRUN_REF_URL}&srun_domain=${SRUN_DOMAIN}"

# get_challenge 的 ip：与 zzdyyy/buaa_gateway_login 一致用 0.0.0.0，由网关返回真实 client_ip；也可在 config 里设 IPADDR 覆盖
LOGIN_PAGE_IP=""
if command -v python3 >/dev/null 2>&1; then
	LOGIN_PAGE_IP="$(extract_ip_from_login_page "$RESULT")"
fi
CHALLENGE_IP="${IPADDR:-${LOGIN_PAGE_IP:-0.0.0.0}}"

# Get challenge number
RESULT=`curl -k -s -b $COOKIEFILE \
--noproxy '*' \
-H "Host: $SRUN_HOST_HEADER" \
-H "Accept: text/javascript, application/javascript, application/ecmascript, application/x-ecmascript, */*; q=0.01" \
-H "DNT: 1" \
-H "X-Requested-With: XMLHttpRequest" \
-H "User-Agent: $UA" \
-H "Sec-Fetch-Mode: cors" \
-H "Sec-Fetch-Site: same-origin" \
-H "Referer: $REF_PORTAL_PC" \
-H "Accept-Language: en-US,en;q=0.9,zh-CN;q=0.8,zh;q=0.7,zh-TW;q=0.6" \
"${SRUN_GET_CHALLENGE_URL}?callback=jQuery112407419864172676014_1566720734115&username="$USERNAME"&ip="$CHALLENGE_IP"&_="$TIMESTAMP`

if [[ -n "${BUAA_DEBUG:-}" ]]; then
	echo "=== DEBUG: get_challenge 完整响应 ===" >&2
	echo "$RESULT" >&2
fi

if command -v python3 >/dev/null 2>&1; then
	parsed="$(jsonp_parse_challenge "$RESULT")"
	if [[ -z "$parsed" ]]; then
		echo "无法解析 get_challenge（需要合法 JSONP）。原始响应：" >&2
		echo "$RESULT" >&2
		rm -f "$COOKIEFILE"
		exit 1
	fi
	IFS=$'\t' read -r CHALLENGE CLIENTIP <<< "$parsed"
else
	echo "警告: 未找到 python3，使用易错的 cut 解析；请安装 python3。" >&2
	CHALLENGE=`echo $RESULT | cut -d '"' -f4`
	CLIENTIP=`echo $RESULT | cut -d '"' -f8`
fi
echo "Challenge: $CHALLENGE"
echo "Client IP: $CLIENTIP"

if [[ "$option" == "login" ]]; then
	# The password is hashed using HMAC-MD5.
	ENCRYPT_PWD=`echo -n $PASSWORD | openssl md5 -hmac $CHALLENGE`
	# Remove the possible "(stdin)= " prefix
	ENCRYPT_PWD=${ENCRYPT_PWD#*= }
	PWD=$ENCRYPT_PWD
	echo "Encrypted PWD: "$PWD

	# Some info is encrypted using srun_bx1 and base64 and substitution ciper
	INFO='{"username":"'$USERNAME'","password":"'$PASSWORD'","ip":"'$CLIENTIP'","acid":"'$AC_ID'","enc_ver":"srun_bx1"}'
	#echo "Info: "$INFO
	ENCRYPT_INFO=$(l_func $INFO $CHALLENGE)
	ENCRYPT_INFO=`echo -ne $ENCRYPT_INFO | openssl enc -base64 -A | tr "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/" "LVoJPiCN2R8G90yg+hmFHuacZ1OWMnrsSTXkYpUq/3dlbfKwv6xztjI7DeBE45QA"`
	echo "Encrypted Info: "$ENCRYPT_INFO

	# Checksum is calculated using SHA1
	CHKSTR=${CHALLENGE}${USERNAME}${CHALLENGE}${ENCRYPT_PWD}${CHALLENGE}${AC_ID}${CHALLENGE}${CLIENTIP}${CHALLENGE}"200"${CHALLENGE}"1"${CHALLENGE}"{SRBX1}"${ENCRYPT_INFO}
	#echo "Check String: "$CHKSTR
	CHKSUM=`echo -n $CHKSTR | openssl dgst -sha1`
	# Remove the possible "(stdin)= " prefix
	CHKSUM=${CHKSUM#*= }
	echo "Checksum: "$CHKSUM

	# URLEncode the "+", "=", "/" in encrypted info.
	URL_INFO=$(echo -n $ENCRYPT_INFO | sed "s/\//%2F/g" | sed "s/=/%3D/g" | sed "s/+/%2B/g")
	#echo "URL Info: "$URL_INFO

	# double_stack：与浏览器 Network 里 srun_portal 查询串一致；默认 0，双栈可试 BUAA_DOUBLE_STACK=1
	DS_STACK="${BUAA_DOUBLE_STACK:-0}"

	# Submit data and login
	LOGIN_OUT=$(curl -k -s -b $COOKIEFILE \
        --noproxy '*' \
	-H "Host: $SRUN_HOST_HEADER" \
	-H "Accept: text/javascript, application/javascript, application/ecmascript, application/x-ecmascript, */*; q=0.01" \
	-H "DNT: 1" \
	-H "X-Requested-With: XMLHttpRequest" \
	-H "User-Agent: $UA" \
	-H "Sec-Fetch-Mode: cors" \
	-H "Sec-Fetch-Site: same-origin" \
	-H "Referer: $REF_PORTAL_PC" \
	-H "Accept-Language: en-US,en;q=0.9,zh-CN;q=0.8,zh;q=0.7,zh-TW;q=0.6" \
	"${SRUN_PORTAL_API_URL}?callback=jQuery112407419864172676014_1566720734115&action=login&username="$USERNAME"&password=%7BMD5%7D"$PWD"&ac_id=$AC_ID&ip="$CLIENTIP"&chksum="$CHKSUM"&info=%7BSRBX1%7D"$URL_INFO"&n=200&type=1&os="$SYSNAME"&name=Macintosh&double_stack="$DS_STACK"&_="$TIMESTAMP)
	echo "srun_portal(login): $LOGIN_OUT"
	if [[ -n "${BUAA_DEBUG:-}" ]]; then
		echo "=== DEBUG: srun_portal 参数 ac_id=$AC_ID ip=$CLIENTIP double_stack=$DS_STACK" >&2
		echo "=== DEBUG: host=$SRUN_HOST_HEADER portal=$SRUN_PORTAL_API_URL challenge=$SRUN_GET_CHALLENGE_URL" >&2
	fi

elif [[ "$option" == "logout" ]]; then
	LOGOUT_OUT=$(curl -k -s -b $COOKIEFILE \
        --noproxy '*' \
	-H "Host: $SRUN_HOST_HEADER" \
	-H "Accept: text/javascript, application/javascript, application/ecmascript, application/x-ecmascript, */*; q=0.01" \
	-H "DNT: 1" \
	-H "X-Requested-With: XMLHttpRequest" \
	-H "User-Agent: $UA" \
	-H "Sec-Fetch-Mode: cors" \
	-H "Sec-Fetch-Site: same-origin" \
	-H "Referer: $REF_PORTAL_PC" \
	-H "Accept-Language: en-US,en;q=0.9,zh-CN;q=0.8,zh;q=0.7,zh-TW;q=0.6" \
	"${SRUN_PORTAL_API_URL}?callback=jQuery112407419864172676014_1566720734115&action=logout&username="$USERNAME"&ac_id=$AC_ID&ip="$CLIENTIP)
	echo "srun_portal(logout): $LOGOUT_OUT"
fi

rm -f "$COOKIEFILE"
