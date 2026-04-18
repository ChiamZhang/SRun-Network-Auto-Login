# SRun Network Auto Login

用命令行登录校园网深蓝（SRun）认证，不用开浏览器。默认按北航 `gw.buaa.edu.cn` 配好，也可以改成国科大、北理工等同一套系统的学校。

`config` 里存账号密码，已写进 `.gitignore`，不要往公开仓库里提交。

上网不涉密，涉密不上网。

---

## Linux / macOS 和 Windows：先看这两件事

两件事不一样：**配置文件放的路径不同**，**敲命令时当前文件夹不同**。下面按这个分开说，再用一张表把「同一功能」两边的命令对齐。

### 配置文件放在哪

| 系统 | 把 `config` 放在哪 |
|------|---------------------|
| **Linux / macOS** | 仓库**根目录**（和 `login.sh` 同级） |
| **Windows** | **`windows` 文件夹里**（和 `Login.ps1` 同级） |

模板任选：`config.example`（北航）、`config.ucas.example`（国科大）、`config.bit.example`（北理工）。复制后**改名为 `config`**，编辑时至少填：

```bash
USERNAME="学号或上网账号"
PASSWORD="密码"
ACID="数字"          # 怎么查见下文「ACID」
```

> 若你使用 `login2.sh`，通常只需填写 `USERNAME`、`PASSWORD`；`ACID` 默认自动抓取，只有自动抓取失败时才需要在 `config` 里补填（或用 `--acid`/`BUAA_ACID` 临时指定）。

Linux / macOS 上复制示例（在仓库根目录执行）：

```bash
cp config.example config
```

Windows 上复制示例（在资源管理器里操作即可，或 cmd）：

```bat
copy config.example windows\config
```

### 运行命令时在哪个目录

| 系统 | 打开终端后要先 |
|------|----------------|
| **Linux / macOS** | `cd` 到仓库**根目录** |
| **Windows** | `cd` 到 **`windows` 子文件夹** |

Linux / macOS 不要用 `sh` 跑，请用 **`bash login.sh`**。可选执行一次：`chmod +x login.sh try-connect.sh protect-connect.sh`。

### 依赖（各管各的）

| 系统 | 需要 |
|------|------|
| **Linux / macOS** | `bash`、`curl`、`openssl`；`login.sh` 建议装 `python3`，**`login2.sh` 必须有 `python3`** |
| **Windows** | **PowerShell 5.1+**、**curl.exe**（Win10 起一般自带）；**不用装 Python** |

### 常用命令对照（同一行左 Linux / 右 Windows）

以下：**左列在仓库根目录执行**；**右列先在 PowerShell 里 `cd windows` 再执行**。

| 做什么 | Linux / macOS | Windows（PowerShell） |
|--------|---------------|----------------------|
| 登录 | `bash login.sh login` | `.\Login.ps1 login` |
| 登录（`login2.sh`，自动抓 ACID） | `bash login2.sh login` | - |
| 注销 | `bash login.sh logout` | `.\Login.ps1 logout` |
| 临时改 ACID 再登录 | `bash login.sh login --acid 67` | `.\Login.ps1 login --acid 67` |
| 未在线才登录 | `bash try-connect.sh` | `.\Try-Connect.ps1` |
| 定时检查、掉线重登 | `bash protect-connect.sh` | `.\Protect-Connect.ps1` |

ACID 参数在两边还支持 `-a`、`--acid=67`、位置参数 `login 67` 等，和 `login.sh` 一致。

### Windows 单独说明（执行策略、cmd、环境变量）

**执行策略**：若提示无法运行脚本，在本机 PowerShell **执行一次**：`Set-ExecutionPolicy -Scope CurrentUser RemoteSigned`。  
若不想改策略，也可以每次让系统 PowerShell 代跑（在任意目录）：`powershell -NoProfile -ExecutionPolicy Bypass -File "完整路径\windows\Login.ps1" login`。

**cmd**：`windows` 目录下有 `Login.cmd`、`Try-Connect.cmd`、`Protect-Connect.cmd`，作用等于调用同名 `.ps1`（例如在 cmd 里：`cd windows` 后 `Login.cmd login`）。

**环境变量**：变量名与 Linux 相同；PowerShell 写法例如 `$env:BUAA_DEBUG='1'`、`$env:BUAA_ACID='67'`。Linux 则是 `BUAA_DEBUG=1 bash login.sh login` 这种。

**`_SRunCommon.ps1`**：给上面几个 `.ps1` 共用，**不要单独运行**。

---

## ACID 是啥、怎么填

浏览器打开学校认证页，成功登录一次，看地址栏或开发者工具 Network 里带 **`ac_id=`** 的那串数字，填进 `config` 的 `ACID`。无线/有线、不同宿舍楼可能数字不同，别直接抄别人的。

`login2.sh` 的规则：

- 默认自动抓取 `ACID`，通常不用手填；
- 只有自动抓取失败时，才需要读 `config` 里的 `ACID`（或临时用 `--acid` / `BUAA_ACID`）；
- `login2.sh` 依赖 `python3`。

如果你想让 `try-connect.sh` 也走 `login2.sh`，可把原 `login.sh` 移走/删除，再把 `login2.sh` 改名为 `login.sh`（`try-connect.sh` 默认调用的是 `login.sh`）。

---

## 换学校、网关和自己学校

国科大、北理工：用对应的 `config.*.example` 复制成 **`config`**（Linux/macOS 放根目录，Windows 放 `windows\`），再改账号密码和 ACID。

别的学校也是 SRun：在**对应路径的那份 `config`** 里改 `SRUN_HOST`、`SRUN_THEME` 等，或按 `config.example` 注释写完整 `SRUN_*_URL`。改完两边脚本都会读同一份配置逻辑。

**有时要动的可选项**（都在 `config.example` 里有注释）：`PROTECT_INTERVAL`（保活间隔秒数）、`IPADDR`（极少数网关要固定本机 IP）、`BUAA_DOUBLE_STACK=1`（双栈网络可试）。调试可加 `BUAA_DEBUG=1`。

---

## 无 Python 时 bash 版会怎样

没装 `python3` 时 `login.sh` 会用 `cut` 硬切字符串，很多学校还能登上去，但不保证一直靠谱。想自测这种路径可以用：

```bash
bash scripts/test-without-python.sh login
```

---

## 想临时改参数、抓调试信息（可选）

不改 `config` 文件也可以，例如：

```bash
BUAA_ACID=67 bash login.sh login
BUAA_DEBUG=1 bash login.sh login
SRUN_HOST="portal.ucas.ac.cn" SRUN_THEME="pro" bash login.sh login
```

Windows 上用前面说的 `$env:变量名 = '值'` 即可。

---

## 文件对照（找脚本时看一眼）

| 文件 | 干啥 |
|------|------|
| `login.sh` | 登录 / 注销 |
| `login2.sh` | 登录 / 注销（自动抓 ACID，依赖 python3） |
| `try-connect.sh` | 未在线才登录 |
| `protect-connect.sh` | 定时检查、掉线重登 |
| `windows/Login.ps1` 等 | Windows 上同上 |
| `windows/*.cmd` | 双击或 cmd 里快捷调用 `.ps1` |
| `scripts/test-without-python.sh` | 测「没有 python3」时 `login.sh` 行为 |

---

## 许可

见 `LICENSE`。
