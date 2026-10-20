# 变更记录

格式遵循 [Keep a Changelog](https://keepachangelog.com/zh-CN/1.1.0/)，版本号遵循 [语义化版本](https://semver.org/lang/zh-CN/)。

## [1.0.0] — 2026-10-20

首个可用版本：WorkBuddy 账号里的模型接入 DeepSeek Harness，工具调用双向互通。

### 新增

- `relay/workbuddy-openai-relay.py`：OpenAI ⇄ WorkBuddy（`/api/v1/runs` + ACP）双向网关
  - `<tool_call>` → OpenAI `tool_calls` 流式输出（支持并行调用、多轮 `<tool_result>` 回填）
  - 上游 429 原样透出，不伪装成超时
  - 图片输入降级为文字占位（不静默丢失）
- `scripts/wb-clean-start.ps1`：硬解模式启动器
  - **自建 serve**（`--auth none --tools "" --system-prompt-file`），让 DSH 提示词真正成为 system
  - 上游零工具权限，工具只能交给 DSH 执行（不再绕过沙箱/审批）
  - token 自动获取：缓存文件 → 从 WorkBuddy 进程内存扫描 JWT
  - node / python / CLI 路径多路自动探测
  - 由 Windows 计划任务托管（父进程 svchost，退出 DSH 不受影响）
- `scripts/wb-scan-token.ps1`：进程内存扫描（`VirtualQueryEx` + `ReadProcessMemory`）
- `scripts/wb-read-env.ps1`：进程环境变量读取（PEB），旧模式获取本地网关密码用
- `scripts/wb-relay-status.ps1`：四面板巡检（serve / relay / token / DSH 配置）
- `scripts/wb-relay-stop.ps1`：停任务 + 释放端口
- `scripts/wb-relay-start.ps1`：旧模式（绑定 WorkBuddy 自己的 serve，保留作 fallback）
- `scripts/probe/workbuddy-acp-probe.ps1`：ACP 链路探测（研究/排障用）
- `ui/wb_bridge_ui.py` + PyInstaller 打包：图形界面
  - 三盏状态灯（5 秒自动刷新）、启动/停止/刷新
  - 关窗口 = 最小化到任务栏（点 × 不会误退出）
  - 托盘菜单（Win11 默认折叠进 `^` 溢出区）
  - 一键「复制诊断报告」（同时落盘 `%TEMP%\wb-diagnose-*.txt`）
  - `--diagnose`：无界面出报告，适合远程排障
- 文档：`REPORT.md`（架构/实测证据/换机预估）、`docs/ARCHITECTURE.md`（协议细节）、
  `docs/RUNBOOK.md`（运维手册）、`deploy/NEW-MACHINE.md`（换机部署清单）

### 踩过并修掉的坑（供后来者避雷）

| 坑 | 现象 | 处理 |
|---|---|---|
| 正则上限太短 | 扫到的 JWT 被截到 300 字符 → 上游 `401 (token-length:300)` | 上限放宽到 4000，字符集补 `=+/` |
| `cmd /c set /p` | 环境变量被截断到 1023 字符 | 改用 PowerShell 读文件设 `$env:` |
| `--tools ""` 被吞 | serve 没禁用工具 | 用单字符串 `-ArgumentList` 传参 |
| `Start-Process` 起的进程 | DSH 退出时被作业对象连带杀掉（`Connection error`） | 改用计划任务托管 |
| ACP 权限模式 | `plan` / `default` 都拦不住上游读写文件 | 改为自建 serve + `--tools ""` |
| PyInstaller onefile | `Could not create temporary directory!`（Defender 拦临时目录执行） | 改用 onedir |
| pystray `run_detached` | 图标 `visible=False`（不显示） | 图标转 RGBA + 显式 `visible = True` |
| 日志文件被占用 | exe 启动报 `PermissionError` 后崩溃 | `RotatingFileHandler(delay=True)` + try/except |

### 已知限制

- 图片输入不可用（上游 runs 接口只收文本）
- 无原生 reasoning 通道（上游不回传思考流）
- `systemMode=full` 每轮发送完整 system，token 成本高于原生路由
- 依赖 WorkBuddy 5.8.3 的 CLI 内部实现，大版本升级需重新核对参数与端点
