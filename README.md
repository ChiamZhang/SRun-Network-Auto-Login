# BeihangLogin

北航校园网网关（`gw.buaa.edu.cn`）命令行认证脚本：**登录**、**按需重连**、**定时保活**。

## （适用于其他同版本的深蓝认证系统！！）

上网不涉密，涉密不上网。

## 详细介绍：

BeihangLogin 是一套面向北航校园网网关 gw.buaa.edu.cn 的命令行小工具，用来在终端里完成深澜（SRun）门户认证，适合不想每次手动打开浏览器、或需要开机/定时自动保活的场景。项目不依赖图形界面，核心脚本是 login.sh：读取同目录下的 config（由 config.example 复制而来），其中需填写 学号（USERNAME）、密码（PASSWORD） 以及门户上的 ACID（即浏览器地址栏或开发者工具 Network 里 srun_portal_pc?ac_id= 后的数字；有线/无线或区域不同可能不同，务必按自己环境核对，填错常出现「看似登录成功却无法上网」）。可选字段 PROTECT_INTERVAL 表示保活脚本的检测间隔（秒），默认 3600。

运行环境需要 bash、curl、openssl 与 python3（用于正确解析 get_challenge 的 JSONP，避免旧式字符串截取导致假登录）。请使用 bash login.sh login / logout 执行，不要用 macOS 自带的 sh（多为 dash）。try-connect.sh 在网关判定未在线时自动调用登录；protect-connect.sh 按 config 中的间隔循环检测，掉线则重登，适合长期挂机。config 已列入 .gitignore，请勿把真实凭据提交到公开仓库。整体流程与浏览器认证一致，仅将账号信息与 ACID 固化在本地配置中，便于脚本化与自动化维护。

# 使用方法

## 依赖

- `bash`、`curl`、`openssl`
- `python3`（解析 `get_challenge` 返回的 JSONP，避免误解析导致假登录）

请用 `**bash login.sh`** 或 `**./login.sh**`（可执行）运行，**不要用 `sh`**。

## 配置 config

1. 复制模板：
  `cp config.example config`
2. 编辑 `config`，填写：
  - **USERNAME**：学号  
  - **PASSWORD**：密码  
  - **ACID**：门户上的 **ac_id**（整数）  
  - **PROTECT_INTERVAL**（可选）：`protect-connect.sh` 的检测间隔（秒），默认 **3600**

### 如何确认自己的 ACID

务必**自己登录一次**校园网（浏览器打开认证页并成功登录），然后查看：

- 地址栏 URL 中形如  
`https://gw.buaa.edu.cn/srun_portal_pc?ac_id=**数字**&...`  
其中的数字即为 **ACID**；或  
- 开发者工具（F12）→ **Network**，筛选 `srun_portal` / `get_challenge`，在请求 URL 里找到 `**ac_id=`**。

无线、有线、不同楼宇可能不同，**不要照搬别人的数字**，以你本机浏览器为准。填错常表现为「看似登录成功但不能上网」或证书报错。

`config` 已列入 `.gitignore`，请勿提交到公开仓库。

## 脚本说明


| 文件                   | 作用                                                     |
| -------------------- | ------------------------------------------------------ |
| `login.sh`           | `login` / `logout`，读取 `config` 中的学号、密码、ACID            |
| `try-connect.sh`     | 若网关判定未在线则调用 `login.sh login`                           |
| `protect-connect.sh` | 按 `config` 里 **PROTECT_INTERVAL**（默认 3600s）检测；未在线则重新登录 |


首次使用建议：

```bash
chmod +x login.sh try-connect.sh protect-connect.sh
bash login.sh login
```

注销：

```bash
bash login.sh logout
```

按需补登（例如开机脚本）：

```bash
bash try-connect.sh
```

长期挂机保活（间隔在 `config` 里配置 **PROTECT_INTERVAL**，默认 3600 秒）：

```bash
bash protect-connect.sh
```

临时改用其它间隔（覆盖 `config`，例如 30 分钟）：

```bash
PROTECT_INTERVAL=1800 bash protect-connect.sh
```

## 调试与可选环境变量

- **BUAA_DEBUG=1**：打印网关部分原始响应，便于对照浏览器 Network。  
- **BUAA_DOUBLE_STACK=1**：若浏览器里 `srun_portal` 带 `double_stack=1` 可尝试。  
- **IPADDR**：极少数环境需在 `config` 里写本机 IP，见 `config.example`。  
- **BUAA_USERNAME / BUAA_PASSWORD / BUAA_ACID**：临时覆盖 `config` 中对应项。

## 许可

见仓库内 `LICENSE`。