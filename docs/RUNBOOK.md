# 运维手册（RUNBOOK）

## 日常

| 想做什么 | 怎么做 |
|---|---|
| 启动 / 重启 | 双击桌面「WorkBuddy中转工具」，或 `.\scripts\wb-clean-start.ps1` |
| 桌面没有图标 | 运行项目根目录的 `一键安装.cmd`（clone 下来是没有快捷方式的） |
| 看状态 | 双击桌面「WorkBuddy中转-状态」；四面板应全绿 |
| 停止 | 双击桌面「WorkBuddy中转-停止」（或在工具界面点「停止」） |
| 换模型 | 在 DSH 的模型下拉里选 `脑力·xxx (WB)`（DSH 重启后可见） |
| 切回原生 | 模型下拉选不带「脑力·」前缀的（默认就是 `deepseek-account`） |

## 三种常见故障

### A. DSH 报 `Connection error`
1. 跑状态脚本 → 【2】relay 是否在跑
2. 没跑 → 双击桌面「WorkBuddy中转工具」，点「启动 / 修复」
3. 在跑但仍报错 → 看 `C:\temp\wb-relay.log` 尾部

### B. DSH 报 429 / 提示"被限流"
上游账号配额或频率限制。等 1~15 分钟，或切回原生模型。relay 已把 429 原样透出，不会伪装成超时。

### C. 启动脚本报「上游未登录 / 401」
token 过期（有效期约 30 天）。处置：
1. 确认 WorkBuddy 已打开并登录（在里面随便发一句话，确保 serve 进程活着）
2. `.\scripts\wb-clean-start.ps1 -RescanToken`
3. 仍失败 → 手动确认能否扫到：`.\scripts\wb-scan-token.ps1 -ProcessId <WorkBuddy serve 的 pid>`
   - 扫到 `bearer len≈1300 eyJ...` → token 正常，问题在别处
   - 只扫到 43 字符的短串 → 那不是 auth token，说明 serve 进程换了或没登录


## 启动脚本说「需要 WorkBuddy 在运行」，但我明明开着

**原因**：不同版本的 WorkBuddy 承载内置 CLI 的进程名不一样 ——
可能是 `WorkBuddy.exe`、`node.exe`（用 node 跑 `codebuddy`）、也可能是 `CodeBuddy.exe`。
早期版本只认 `WorkBuddy.exe`，在别的机器上会漏判。

**现在的做法**：不猜进程名。把所有可疑进程（`WorkBuddy*` / `CodeBuddy*` / 命令行含
`codebuddy` 或 `workbuddy` 的 node）都列出来，**逐个扫内存，谁里面有 JWT 就用谁**。
顺带会把「非管理员读不到内存」这种情况单独提示出来。

**自己确认的办法**：

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\wb-doctor.ps1
```

报告会列出：

| 节 | 内容 |
|---|---|
| 1 | 系统 / 是否管理员（读进程内存需要） |
| 2 | WorkBuddy 安装路径与版本 |
| 3 | **所有相关进程**（名字 / pid / 内存 / 命令行 / 是否含 `--serve`） |
| 4 | 每个进程能否读取（`OpenProcess` 实测） |
| 5 | **每个进程里有没有 JWT**（逐进程扫内存） |
| 6 | 缓存 token 与 `settings.psd1` 状态 |
| 7 | 端口 8791 / 8787 与两个计划任务 |
| 8 | 结论与下一步建议 |

报告不含 token 本身，可以直接发给作者。

## DSH 报 502（由于目标计算机积极拒绝，无法连接）

**含义**：DSH 连 `127.0.0.1:8787` 被拒 —— relay 没在跑。不是网络问题，也不是配置问题。

**处理**：双击桌面「WorkBuddy中转工具」→ 点「启动 / 修复」。

**为什么会没跑**（这条链踩过三个坑，都修了）：

| 坑 | 现象 | 现在怎么做 |
|---|---|---|
| 计划任务用 `/sc once`（一次性时间触发） | 建好当时能用，重启后永不再起 | 改为 `/sc onlogon`（登录即起） |
| 普通权限下 `schtasks /create` 被拒（Access denied） | 任务建不出来，服务根本起不来 | 失败自动回落 **WMI 直接启动**（父进程 WmiPrvSE，同样不受 DSH 退出影响，且不需要管理员） |
| 启动文件夹里放 `.cmd`，内容含中文路径 | `C:\Users\安山` 被代码页写成 `C:\Users\??` 或传参失败 | 改放 **`.lnk` 快捷方式**（内部 UTF-16，不受代码页影响） |

**自启现状**：

- 计划任务 `WorkBuddyCleanServe` / `WorkBuddyRelay`（`onlogon`，有权限时）—— 优先
- 启动文件夹 `WorkBuddyBridge.lnk` —— 兜底，登录后静默跑一次
- 静默模式日志：`C:\temp\wb-autostart.log`
- 强制重启：双击桌面图标 → 启动 / 修复

## 关键路径速查

| 用途 | 路径 |
|---|---|
| 账号 token（等同凭据，勿外传） | `C:\temp\wb-jwt.txt` |
| relay 配置（base/port/systemMode） | `C:\temp\wb-relay-config.json` |
| 自建 serve 的 system prompt | `C:\temp\wb-sysprompt.txt`（权威副本在 `config/wb-sysprompt.txt`） |
| 自建 serve 的启动脚本（计划任务调用） | `C:\temp\wb-clean-serve.ps1` |
| relay 日志 | `C:\temp\wb-relay.log` |
| 内存扫描候选 | `C:\temp\wb-mem-candidates.txt` |
| 计划任务 | `WorkBuddyCleanServe`（serve）/ `WorkBuddyRelay`（relay） |

## 调参

`C:\temp\wb-relay-config.json`：

```json
{"base":"http://127.0.0.1:8791","password":"x","port":8787,"systemMode":"full"}
```

| 键 | 取值 | 说明 |
|---|---|---|
| `systemMode` | `full` / `tail` / `none` | full=DSH 提示词全量作为 system；tail=尾部 8K + 过滤；none=不传 |
| `systemTail` | 整数 | `tail` 模式保留的字符数 |
| `port` | 8787 | relay 端口，改了要同步 DSH 的 baseURL |

改完重启 relay（状态脚本里点停止再启动即可）。

## 换机

见 `REPORT.md` 第 6 节。最短路径：
1. 改 `config/settings.psd1` 的 `CodebuddyCli`（和必要时 `PythonExe` / 端口）
2. 拷整个项目目录，在目标机双击 `一键安装.cmd`（会重建快捷方式、自动探测 CLI 路径）
3. 目标机上打开 WorkBuddy 并登录，发一句话
4. 跑启动脚本（token 会在新机器重新扫描，不要拷 `wb-jwt.txt`）
5. 在目标机的 DSH profile 里加 `workbuddy` provider 与 `WORKBUDDY_LOCAL_KEY`

## 升级 WorkBuddy 之后

先跑 `wb-scan-token.ps1` 确认还能扫到 JWT；再跑启动脚本。
如果 serve 起不来，检查 CLI 是否仍支持 `--serve/--tools/--system-prompt-file`：

```powershell
node "D:\WorkBuddy\resources\app.asar.unpacked\cli\bin\codebuddy" --help
```

参数变了就改 `scripts/wb-clean-start.ps1` 里生成 `$serveLines` 的那段。
接口路径变了就改 `relay/workbuddy-openai-relay.py` 里的 `run_agent` / `_acp_method`。

## 中文用户名导致 git 走 SSH 失败（Git for Windows 的坑）

**现象**（`git push` / `git clone` 时）：

```
Could not create directory '/c/Users/\260\262\311\275/.ssh' (No such file or directory).
Failed to add the host to the list of known hosts (/c/Users/\260\262\311\275/.ssh/known_hosts).
git@github.com: Permission denied (publickey).
```

**原因**：Git for Windows 自带的 MSYS 版 `ssh.exe`（`C:\Program Files\Git\usr\bin\ssh.exe`）
无法正确处理非 ASCII 用户名，把 `C:\Users\安山` 按 GBK 字节转成
`/c/Users/\260\262\311\275`（`\260\262`＝"安"，`\311\275`＝"山"），这个路径不存在，于是：

- 写不进 `known_hosts` → 每次连接都问 "continue connecting?"
- 找不到 `~/.ssh/id_ed25519` → `Permission denied (publickey)`

**修复**：让 git 改用 Windows 自带的 OpenSSH（对中文路径正常）：

```powershell
git config --global core.sshCommand "C:/Windows/System32/OpenSSH/ssh.exe"
ssh -T git@github.com        # 应输出 Hi <你的用户名>! You've successfully authenticated
```

验证：`git ls-remote origin` 退出码 0 即通。

撤销：`git config --global --unset core.sshCommand`

> 这条坑与项目本身无关，但凡是中文用户名 + Git for Windows 都会遇到，
> 而且报错信息（乱码路径）很容易被误判成 key 没配好。
