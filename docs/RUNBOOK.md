# 运维手册（RUNBOOK）

## 日常

| 想做什么 | 怎么做 |
|---|---|
| 启动 / 重启 | 双击桌面「启动WorkBuddy中转.cmd」，或 `.\scripts\wb-clean-start.ps1` |
| 看状态 | 双击「WorkBuddy中转状态.cmd」；四面板应全绿 |
| 停止 | 双击「停止WorkBuddy中转.cmd」 |
| 换模型 | 在 DSH 的模型下拉里选 `脑力·xxx (WB)`（DSH 重启后可见） |
| 切回原生 | 模型下拉选不带「脑力·」前缀的（默认就是 `deepseek-account`） |

## 三种常见故障

### A. DSH 报 `Connection error`
1. 跑状态脚本 → 【2】relay 是否在跑
2. 没跑 → 双击启动脚本
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
2. 拷整个项目目录 + 桌面四个 cmd
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
