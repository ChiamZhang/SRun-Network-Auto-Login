#!/bin/bash
# 若网关报告未在线则执行登录。依赖同目录 config 与 login.sh。
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [[ -f "$SCRIPT_DIR/config" ]]; then
	# shellcheck source=/dev/null
	source "$SCRIPT_DIR/config"
fi

SRUN_SCHEME="${SRUN_SCHEME:-https}"
SRUN_HOST="${SRUN_HOST:-gw.buaa.edu.cn}"
SRUN_RAD_USER_INFO_URL="${SRUN_RAD_USER_INFO_URL:-${SRUN_SCHEME}://${SRUN_HOST}/cgi-bin/rad_user_info}"

CLI_ACID=""
if [[ $# -gt 0 ]]; then
	case "$1" in
		help|-h|--help)
			cat <<'EOF'
用法:
  bash try-connect.sh
  bash try-connect.sh --acid 67
  bash try-connect.sh -a 67
  bash try-connect.sh 67

说明:
  仅在检测到未在线时触发登录。
  ACID 优先级：命令行参数 > BUAA_ACID > config 的 ACID
EOF
			exit 0
			;;
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
			CLI_ACID="$1"
			shift
			;;
	esac
fi

if [[ $# -gt 0 ]]; then
	echo "未知参数: $1" >&2
	exit 1
fi

online=$(curl -sS -k --noproxy '*' "$SRUN_RAD_USER_INFO_URL" 2>/dev/null) || online=""
if ! grep -q "not_online_error" <<< "$online"; then
	echo "online: $(cut -d, -f1 <<< "$online")"
	exit 0
fi

if [[ -n "$CLI_ACID" ]]; then
	exec bash "$SCRIPT_DIR/login.sh" login --acid "$CLI_ACID"
else
	exec bash "$SCRIPT_DIR/login.sh" login
fi
