# SRun Network Auto Login

面向深蓝（SRun）认证系统的命令行工具。BUAA（`gw.buaa.edu.cn`）为默认示例；同时支持 UCAS、BIT 等其他 SRun 系统。

上网不涉密，涉密不上网。

---

## 功能特性

- **登录/注销**：支持 `bash login.sh login` 和 `bash login.sh logout`
- **按需补登**：检测未在线时自动登录（`try-connect.sh`）
- **定时保活**：后台定期检测，掉线自动重新登录（`protect-connect.sh`）
- **跨学校适配**：通过配置参数支持 BUAA、UCAS、BIT 等不同学校深蓝系统的网关
- **灵活的 ACID 指定**：支持命令行临时覆盖，适应不同地点网络的 ACID 变化
- **脚本化与自动化**：无需浏览器，纯命令行流程，易于开机自启或定时任务集成

---

## 环境依赖

必需：
- `bash`、`curl`、`openssl`

**强烈推荐**安装 `python3`：供 `login.sh` 解析 `get_challenge` 的 JSONP；若无 `python3`，脚本会退回用 `cut` 截取字段，在大部分网关上仍可能登录成功，但**网关响应格式一变就容易错位或假登录**。

**请使用 `bash login.sh` 或 `./login.sh` 运行，勿用 macOS 自带的 `sh`（多为 dash）。**

---

## 快速开始

### 1. 准备配置文件

根据你的学校选择对应的配置模板：

- **BUAA（北京航空航天大学）**：`cp config.example config`
- **UCAS（中国科学院大学）**：`cp config.ucas.example config`
- **BIT（北京理工大学）**：`cp config.bit.example config`
- **其他系统**：见下文"配置指南 → 自定义系统"

### 2. 编辑配置文件

编辑 `config`，填写基本信息：

```bash
USERNAME="你的学号（或用户名）"
PASSWORD="你的密码"
ACID="99"  # 门户登录窗口地址栏的 ac_id 参数值
```

### 3. 首次登录测试

```bash
chmod +x login.sh try-connect.sh protect-connect.sh
bash login.sh login
```

### Windows（PowerShell）

仓库内 [`windows/`](windows/) 提供与 `login.sh` / `try-connect.sh` / `protect-connect.sh` 等价的 PowerShell 脚本（无需 bash、无需 Python；需 **Windows 10+** 自带的 `curl.exe`）。

1. 将根目录的 `config.example`（或 `config.ucas.example` / `config.bit.example`）复制为 **`windows\config`**（与脚本同目录；`config` 已在 `.gitignore`，勿提交）。
2. 编辑 `windows\config`，填写 `USERNAME`、`PASSWORD`、`ACID` 等（格式与 bash 版相同：`KEY="值"`）。
3. 在 **PowerShell** 中执行（若提示禁止运行脚本，可先执行 `Set-ExecutionPolicy -Scope CurrentUser RemoteSigned` 或使用下方绕过方式）：

```powershell
cd windows
powershell -ExecutionPolicy Bypass -File .\Login.ps1 login
powershell -ExecutionPolicy Bypass -File .\Try-Connect.ps1
powershell -ExecutionPolicy Bypass -File .\Protect-Connect.ps1
```

临时指定 ACID、调试等与 bash 版一致：`-Acid 67`、`$env:BUAA_DEBUG='1'`、`$env:BUAA_DOUBLE_STACK='1'` 等。

---

## 使用方法

### 登录

```bash
bash login.sh login
```

输出登录状态信息。若需要临时使用不同的 ACID（如在校内不同网络环境），可指定：

```bash
bash login.sh login --acid 67           # 方式1：--acid 参数
bash login.sh login -a 67               # 方式2：-a 简写
bash login.sh login 67                  # 方式3：位置参数
```

### 注销

```bash
bash login.sh logout
```

### 按需补登（检测未在线则登录）

```bash
bash try-connect.sh
```

检测到未在线时才会触发登录。可与开机脚本或定时任务配合使用。同样支持临时 ACID 指定：

```bash
bash try-connect.sh --acid 67
```

### 定时保活（后台守护）

```bash
bash protect-connect.sh
```

按 `config` 中的 `PROTECT_INTERVAL`（默认 3600 秒）周期性检测，未在线则自动重新登录。适合长期挂机保活。按 `Ctrl+C` 或 `kill` 进程停止。

也可临时改用其他检测间隔（例如 30 分钟）：

```bash
PROTECT_INTERVAL=1800 bash protect-connect.sh
```

---

## 配置指南

### 基础配置（BUAA 默认）

复制 `config.example` 为 `config`，编辑以下必需字段：

| 字段 | 说明 | 示例 |
|------|------|------|
| `USERNAME` | 学号或用户名 | `2024001` |
| `PASSWORD` | 登录密码 | 你的密码 |
| `ACID` | 门户 ac_id（整数） | `67` |

可选字段：

| 字段 | 说明 | 默认值 |
|------|------|-------|
| `PROTECT_INTERVAL` | `protect-connect.sh` 检测间隔（秒） | `3600` |
| `IPADDR` | 向网关传递的本机 IP（极少需要） | — |
| `BUAA_DEBUG` | 调试模式（打印原始响应）| — |
| `BUAA_DOUBLE_STACK` | 若浏览器中 `srun_portal` 带 `double_stack=1` 可尝试设 1 | — |

#### 如何确认自己的 ACID

1. 打开浏览器，访问学校认证门户（例如 BUAA 为 `https://gw.buaa.edu.cn`）
2. 成功登录一次
3. 查看地址栏 URL 或开发者工具 Network，找到形如 `srun_portal_pc?ac_id=**数字**` 的请求
4. 那个数字就是你的 ACID，填入 `config`

**注意**：不同宿舍、楼宇、网络接入点的 ACID 可能不同；无线和有线也可能不同。务必按你现在的网络环境确认，不要照搬他人的值；填错常表现为"看似登录成功但不能上网"。

---

### 扩展到其他深蓝系统（UCAS、BIT、自定义）

#### 方式1：使用预配置示例（推荐）

仓库已为常见系统准备了配置示例：

```bash
# UCAS 中国科学院大学
cp config.ucas.example config

# BIT 北京理工大学
cp config.bit.example config
```

编辑相应的 `config` 文件，只需要改：
- `USERNAME` 和 `PASSWORD`
- `ACID`（按该校园网门户确认）

#### 方式2：自定义配置参数（适应其他 SRun 系统）

如果你的学校不在上述列表中，但使用同版本的 SRun 系统，可通过 `SRUN_*` 参数手动适配。编辑 `config` 文件，调整网关连接参数：

**快速适配**（只改域名、协议、theme）：

```bash
# 例如系统网关为 https://portal.your-university.edu.cn
SRUN_SCHEME="https"
SRUN_HOST="portal.your-university.edu.cn"
SRUN_THEME="pro"  # 按实际 theme 参数调整
SRUN_REF_URL="portal.your-university.edu.cn"  # 与 SRUN_HOST 一致或按需修改
```

**完整适配**（API 端点路径不同场景）：

```bash
# 若端点路径不同，直接指定完整 URL（优先级更高）
SRUN_SCHEME="https"
SRUN_HOST="portal.example.com"
SRUN_LOGIN_PAGE_URL="https://portal.example.com/srun_portal_pc?ac_id=1&theme=custom"
SRUN_GET_CHALLENGE_URL="https://portal.example.com/cgi-bin/get_challenge"
SRUN_PORTAL_API_URL="https://portal.example.com/cgi-bin/srun_portal"
SRUN_RAD_USER_INFO_URL="https://portal.example.com/cgi-bin/rad_user_info"
```

这样 `login.sh`、`try-connect.sh`、`protect-connect.sh` 会统一使用你配置的网关地址和接口，而不再写死 BUAA 参数。

可参考 `config.example` 文件的详细注释了解各参数含义。

---

## 脚本说明

| 文件 | 作用 |
|-----|------|
| `login.sh` | 核心脚本，支持 `login` / `logout` 命令，读取 `config` 中的凭证和 ACID 进行认证 |
| `try-connect.sh` | 检测脚本：若网关判定未在线，自动调用 `login.sh login` 进行补登 |
| `protect-connect.sh` | 守护脚本：后台定期检测（间隔可配），掉线时自动重新登录，适合长期挂机 |
| `windows/Login.ps1` | Windows 下登录/注销（PowerShell + curl.exe） |
| `windows/Try-Connect.ps1` | Windows 下按需补登 |
| `windows/Protect-Connect.ps1` | Windows 下定时常驻保活 |
| `scripts/test-without-python.sh` | 在排除 `python3` 的 PATH 下调用 `login.sh`，用于自测 `cut` 回退 |

config 文件已列入 `.gitignore`，不会被提交到仓库，你的凭证信息保持本地私密。

---

## 调试与环境变量

运行时可通过环境变量临时修改配置（不修改 `config` 文件）：

### 凭证临时覆盖
- `BUAA_USERNAME=xxx` —— 临时覆盖用户名
- `BUAA_PASSWORD=xxx` —— 临时覆盖密码
- `BUAA_ACID=67` —— 临时覆盖 ACID（同 CLI `--acid` 参数）

示例：
```bash
BUAA_ACID=67 bash login.sh login
```

### 网关连接参数临时覆盖
- `SRUN_SCHEME`、`SRUN_HOST`、`SRUN_THEME`
- `SRUN_*_URL`（各个 API 的完整 URL）

示例：
```bash
SRUN_HOST="portal.ucas.ac.cn" SRUN_THEME="pro" bash login.sh login
```

### 调试选项
- `BUAA_DEBUG=1` —— 打印网关返回的部分原始响应（便于对照浏览器 Network），调试网络请求问题
- `BUAA_DOUBLE_STACK=1` —— 某些双栈网络环境下需要尝试

示例：
```bash
BUAA_DEBUG=1 bash login.sh login
```

---

## 目前已知可用情况

| 学校/机构 | 系统类型 | 配置文件 |
|----------|---------|--------|
| BUAA（北京航空航天大学） | SRun | `config.example` |
| UCAS（中国科学院大学） | SRun | `config.ucas.example` |
| BIT（北京理工大学） | SRun | `config.bit.example` |
| 其他 SRun 系统 | — | 见上文"自定义配置参数" |

如果你使用并成功适配了其他系统，欢迎 issue 或 PR 分享配置示例。

---

## 许可

见仓库内 `LICENSE`。
