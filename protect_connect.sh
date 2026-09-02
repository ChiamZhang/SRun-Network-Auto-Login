#!/bin/bash
# 周期性检测校园网认证状态，掉线则自动重新登录。
# 检测间隔：优先使用环境变量 PROTECT_INTERVAL，否则读 config 里的 PROTECT_INTERVAL，默认 3600 秒。
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
_SAVED_PI="${PROTECT_INTERVAL-}"
if [[ -f "$SCRIPT_DIR/config" ]]; then
	# shellcheck source=/dev/null
	source "$SCRIPT_DIR/config"
fi
INTERVAL="${_SAVED_PI:-${PROTECT_INTERVAL:-3600}}"
SRUN_SCHEME="${SRUN_SCHEME:-https}"
SRUN_HOST="${SRUN_HOST:-gw.buaa.edu.cn}"
SRUN_RAD_USER_INFO_URL="${SRUN_RAD_USER_INFO_URL:-${SRUN_SCHEME}://${SRUN_HOST}/cgi-bin/rad_user_info}"

is_offline() {
	local out
	out=$(curl -sS -k --noproxy '*' "$SRUN_RAD_USER_INFO_URL" 2>/dev/null) || return 0
	grep -q "not_online_error" <<< "$out"
}

log() {
	echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"
}

if ! [[ "$INTERVAL" =~ ^[0-9]+$ ]] || [[ "$INTERVAL" -lt 60 ]]; then
	echo "PROTECT_INTERVAL 须为不小于 60 的整数（秒）" >&2
	exit 1
fi

log "protect-connect 启动，检测间隔 ${INTERVAL}s。Ctrl+C 结束。"

while true; do
	if is_offline; then
		log "未在线，尝试登录…"
		if bash "$SCRIPT_DIR/login.sh" login; then
			:
		else
			log "login.sh 退出码非 0，${INTERVAL}s 后再检测"
		fi
	else
		log "仍在线"
	fi
	sleep "$INTERVAL"
done
