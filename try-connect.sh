#!/bin/bash
# 若网关报告未在线则执行登录。依赖同目录 config 与 login.sh。
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

online=$(curl -sS -k --noproxy '*' "https://gw.buaa.edu.cn/cgi-bin/rad_user_info" 2>/dev/null) || online=""
if ! grep -q "not_online_error" <<< "$online"; then
	echo "online: $(cut -d, -f1 <<< "$online")"
	exit 0
fi

exec bash "$SCRIPT_DIR/login.sh" login
