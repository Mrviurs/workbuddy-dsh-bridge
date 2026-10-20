# 变更记录

格式遵循 [Keep a Changelog](https://keepachangelog.com/zh-CN/1.1.0/)，版本号遵循 [语义化版本](https://semver.org/lang/zh-CN/)。

## [Unreleased]

### 变更

- **许可证从 MIT 改为 [Personal-Use & Commercial-By-Permission License v1.1](LICENSE)**（双许可模式）：
  个人非商业使用免费、无需申请；**商业使用需事先取得书面授权**（开 issue 标题 `[Commercial License]`）。
  另有若干用途**即使获得授权也永远不允许**（转售他人服务、做中转站对外供 API、
  批量账号 / 代他人提取凭据、绕过官方付费、移除许可声明后分发）。
  因为商用不是自动授予，本项目**不属于 OSI 定义的"开源软件"**，准确说法是 source-available + dual licensing。
- 新增 [DISCLAIMER.md](DISCLAIMER.md)（中文）与 [DISCLAIMER.en.md](DISCLAIMER.en.md)（English）：
  逐条列明软件的真实行为（读进程内存 / 本地存 token / 注册计划任务 / 转发对话）、
  账号与技术风险、明确禁止用途、担保与责任限制、合规责任归属。
- README 顶部免责段扩写为六节摘要，并加 `OSI open source: no` 徽章，避免误导。
- 新增 [傻瓜手册（中文）](docs/GUIDE.zh-CN.md) 与 [Idiot-Proof Guide](docs/GUIDE.md)。
- 新增商用授权条款模板 [COMMERCIAL-TERMS.md](COMMERCIAL-TERMS.md)（中文）/
  [COMMERCIAL-TERMS.en.md](COMMERCIAL-TERMS.en.md)（English）：范围勾选、期限、费用、署名、
  责任上限、六条不可授权的红线，附「收到商用询问时的回复模板」与签署前自查清单。

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

### 修复：装完之后 DSH 里根本没有模型

**现象**：跑完 `一键安装.cmd`，桥起来了、三盏灯全绿，但 DSH 的模型下拉里找不到「脑力·」。

**根因**：`install.ps1` 只负责「把桥架起来」，**完全没有碰 DSH 的配置** ——
`cordis.patch.yml` 里的 provider 段和 `.credentials.yaml` 里的 `refs` 都得手工加。
手册却直接跳到「在 DSH 里选模型」，中间的鸿沟没人填。

**修法**：新增 `scripts/wb-configure-dsh.ps1`，并接进安装流程（现在是 6 步）：

- 遍历 `<DSH_HOME>\profiles\*\cordis.patch.yml`
- 已含 `workbuddy` → 跳过（幂等，可重复运行）
- 已有 `llm-pi-ai` 条目但没有 `providers:` → 在 `config:` 下新建并插入
- 已有 `providers:` → 在其下追加（**保留原有 provider**）
- 完全没有 `llm-pi-ai` → 文件末尾追加完整条目
- 跳过明显是客户端（web 界面）的 profile，避免污染配置
- `.credentials.yaml` 缺 `WORKBUDDY_LOCAL_KEY` 则补进 `refs:`
- 每次改动都先备份为 `*.bak-<时间戳>`

三种 profile 形态都实测过（含 YAML 解析校验）：

| 场景 | 结果 |
|---|---|
| 有 llm-pi-ai、无 providers | 插入成功，原有 `someOtherOption` 等配置保留 |
| 已有 providers（deepseek-account / kimi） | 追加成功，三个 provider 并存 |
| 没有 llm-pi-ai 条目 | 末尾自动建条目 |

安装脚本结尾和文档都加了醒目提示：**必须完全退出 DSH 再打开**（关窗口不算）。

### 修复：取 token 时只认 `WorkBuddy.exe`（换机必失败）

**现象**：换到另一台电脑，WorkBuddy 明明开着、也发过消息，启动脚本却报
「需要 WorkBuddy 在运行（用来取 token）」。

**根因**：检测写死了 `Get-CimInstance Win32_Process -Filter "Name='WorkBuddy.exe'"`
并要求命令行同时含 `codebuddy` 和 `--serve`。实测发现不同构建里承载 CLI 的进程名不同：

| 进程 | 实测命令行 |
|---|---|
| `node.exe` pid 12800 | `node "...\cli\bin\codebuddy" --serve --port 8790 ...` ← **真正的 serve** |
| `WorkBuddy.exe` pid 25848 | `WorkBuddy.exe ...sidecar-entry.js --token ... --control-pipe-uuid ...`（不含 codebuddy/--serve） |

所以按 `WorkBuddy.exe` 过滤永远找不到 serve。作者本机因为一直有 token 缓存，
没有触发过这条路径，问题被掩盖了。

**修法**（不再猜进程名）：

- 候选范围放宽为 `WorkBuddy*` / `CodeBuddy*` / 命令行含 `codebuddy|workbuddy` 的 `node*`
- 命令行含 `--serve` 的优先，其余作为兜底
- **逐个进程扫内存，谁里面有 JWT 就用谁**；全失败时打印每个进程的扫描结果
- 非管理员时额外提示「若 WorkBuddy 以管理员运行，读不到它的内存」
- `install.ps1` 的运行检测同步放宽

**新增 `scripts/wb-doctor.ps1`**（只读取证）：系统/管理员状态、WorkBuddy 安装路径与版本、
全部候选进程及命令行、`OpenProcess` 可读性实测、逐进程 JWT 扫描结果、缓存与配置状态、
端口与计划任务、结论。报告存 `%TEMP%\wb-doctor-<时间>.txt`，不含 token，可直接发给作者。

顺带修掉两个 PowerShell 陷阱：函数名 `H` 撞上内置别名 `Get-History`；
`@($a + 'b', $c)` 因逗号优先级被拼成一个字符串。

### 修复：分发可用性（别人 clone 下来根本用不了）

发布后发现文档默认"桌面上已经有快捷方式"、`desktop/*.cmd` 里写死了作者本机路径、
而仓库里又不含 exe —— 别人 clone 下来按手册操作，第一步就卡死。

- **`desktop/*.cmd` 改为相对路径**：`%~dp0..\scripts\xxx.ps1`，在任何位置都能跑
  （原来写的是 `%USERPROFILE%\Documents\deepseek-harness\...\workbuddy-dsh-bridge`，只有作者机器存在）
- **新增 `install.ps1` + `一键安装.cmd`**：clone 后的唯一入口
  · 检查 node / python / WorkBuddy 是否就绪
  · **自动探测 WorkBuddy 的 codebuddy CLI 路径**并写进 `settings.psd1`（免去手填）
  · 自动打包图形界面（有 PyInstaller 时）
  · 在桌面创建「WorkBuddy中转工具 / -状态 / -停止」三个快捷方式
  · 首次启动 + 自检。重复运行安全（幂等）
- 手册（中英）从"四步"改成"五步"，新增第 2 步"安装（只需一次）"，
  并明确写了"刚 clone 下来桌面上没有任何图标，exe 是本机现打包的"
- 手册第 4 步补充：DSH 下拉里没有「脑力·」时，说明该机的 DSH 还没接上 provider
- RUNBOOK / REPORT / NEW-MACHINE / README / bug_report 模板里所有
  "双击桌面「xxx.cmd」"、"双击 exe"的表述，统一为安装后真实存在的图标名
- CI 的 PowerShell 语法检查现已覆盖根目录的 `install.ps1`

### 仓库工程化（推送前审计）

- `.github/workflows/ci.yml`：Python 语法、PowerShell 语法、配置模板可解析、
  凭据特征扫描（特征串拆分拼接，避免扫描器自命中）、本机配置未被追踪
- `.github/ISSUE_TEMPLATE/bug_report.yml` + `config.yml` + `PULL_REQUEST_TEMPLATE.md`
- `requirements.txt`（pystray / Pillow / pyinstaller）、`.gitattributes`（脚本 CRLF、其余 LF）
- 运行时目录 `C:\temp` 缺失时自动创建（7 个脚本 + relay + UI 三层兜底）
- **relay 会话自愈**：上游 serve 重启会让 ACP 会话失效，现在首次失败会自动重置会话并重试一次
  （429 限流不重试，避免放大配额消耗）
- **启动脚本三重防护**：
  - 缺 `config/settings.psd1` 时自动从示例复制并提示要改哪一行
  - `CodebuddyCli` 还是 `<占位符>` 时报明确错误（而不是"找不到 CLI"）
  - 计划任务命令超过 261 字符（schtasks 上限）时提前拦截并建议换短路径
- `settings.psd1` 去掉不生效的 `RuntimeDir` 字段（运行时目录固定 `C:\temp`，由脚本自动创建）

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
