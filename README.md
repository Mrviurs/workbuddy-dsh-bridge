# workbuddy-dsh-bridge

把 **WorkBuddy**（CodeBuddy 桌面端）账号里的模型，接成 **DeepSeek Harness** 的一个 OpenAI 兼容 provider。

做到三件原本做不到的事：

1. **DSH 的提示词真正作为 system 生效** —— 不是塞进 user 消息当"资料"
2. **上游零工具权限** —— `--tools ""`，工具只能交给 DSH 执行，不再绕过沙箱与审批
3. **工具调用双向互通** —— `<tool_call>` ⇄ OpenAI `tool_calls`，支持并行、多轮回填

> 原理一句话：WorkBuddy 安装目录里自带 `codebuddy` CLI。用它自己的账号 token
> 起一个**我们控制的** `--serve` 实例，再用一个 Python 网关翻成 OpenAI 接口。

---

## 免责声明（先读）

- 本项目**不是** WorkBuddy / CodeBuddy / DeepSeek 的官方集成，与上述产品无隶属关系。
- 它复用**你自己账号**的额度，适用于你自己的机器。请自行确认符合服务方条款；不要拿它做二次分发或商业转售。
- token 通过读取**你自己启动的进程内存**获得，只存本机。详见 [SECURITY.md](SECURITY.md)。
- 它依赖 WorkBuddy 客户端内部接口（`/api/v1/runs`、ACP、CLI 参数）。**对方升级可能让它失效**，这是预期风险。
- 仅供个人在本机自用：serve 绑 `127.0.0.1` 且 `--auth none`，**不要暴露到公网**。

---

## 能力与限制

| 项 | 状态 |
|---|---|
| 工具调用（含并行 / 多轮回填） | ✅ |
| 沙箱与审批（执行权在 DSH 侧） | ✅ |
| DSH system prompt 作为真 system | ✅ |
| 图片输入 | ❌ 只传文本，图片降级为占位说明 |
| 原生 reasoning 流 | ❌ 只有最终文本与工具调用 |
| token 成本 | ⚠️ 偏高（`systemMode=full` 每轮送完整 system） |
| 稳定性 | ⚠️ 依赖上游版本，大版本升级需重新核对 |

---

## 快速开始

### 前置条件

- Windows 10/11
- **WorkBuddy 已安装并登录**，且在界面里**至少发过一句话**（token 从它的 serve 进程内存取）
- **Node.js 18+**（缺失时会自动用 WorkBuddy 自带的 `~/.workbuddy/binaries/node/versions/*/node.exe`）
- **Python 3.8+**（要 `pythonw.exe`，relay 用它跑）
- DeepSeek Harness（否则桥起来了也没人用）

### 三步

```powershell
# 0) 复制模板配置（第一次需要）
copy config\settings.example.psd1 config\settings.psd1
notepad config\settings.psd1        # 只改 CodebuddyCli 为你的 WorkBuddy 安装路径
```

```powershell
# 1) 启动：取 token → 起自建 serve(8791) → 起 relay(8787) → 双向自测
Set-ExecutionPolicy -Scope Process Bypass -Force
.\scripts\wb-clean-start.ps1
```

```powershell
# 2) 在 DSH 的 profile 里加 provider（见 config\cordis.patch.example.yml）
#    并在 .credentials.yaml 的 refs: 下加 WORKBUDDY_LOCAL_KEY
#    然后重启 DSH，模型下拉里会出现「脑力·xxx」
```

想要图形界面：构建（见下）后双击 `ui\dist\WorkBuddyRelayUI\WorkBuddyRelayUI.exe`。

---

## 目录结构

```
workbuddy-dsh-bridge/
├─ README.md / CHANGELOG.md / SECURITY.md / LICENSE
├─ REPORT.md                      架构、实测证据、换机预估
├─ docs/
│  ├─ ARCHITECTURE.md             协议细节（升级 WorkBuddy 时照这里改）
│  └─ RUNBOOK.md                  运维：故障处置 / 调参 / 换机
├─ deploy/
│  └─ NEW-MACHINE.md              换到另一台电脑的部署清单
├─ relay/
│  └─ workbuddy-openai-relay.py   OpenAI ⇄ WorkBuddy 网关（工具调用双向翻译）
├─ scripts/
│  ├─ wb-clean-start.ps1          【主入口】硬解启动：token → serve → relay → 自测
│  ├─ wb-relay-status.ps1         四面板巡检（serve / relay / token / DSH）
│  ├─ wb-relay-stop.ps1           停任务 + 释放端口
│  ├─ wb-scan-token.ps1           进程内存扫 JWT（VirtualQueryEx + ReadProcessMemory）
│  ├─ wb-read-env.ps1             读进程环境变量（PEB）
│  ├─ wb-relay-start.ps1          旧模式（绑 WorkBuddy 自己的 serve，fallback）
│  └─ probe/workbuddy-acp-probe.ps1  ACP 链路探测（研究用）
├─ ui/
│  ├─ wb_bridge_ui.py             tkinter 图形界面（托盘 / 诊断报告）
│  └─ app.ico
└─ config/
   ├─ settings.example.psd1       ★ 复制成 settings.psd1 再改（后者不进仓库）
   ├─ wb-sysprompt.txt            自建 serve 的 system prompt 模板
   ├─ cordis.patch.example.yml    DSH provider 片段
   └─ credentials.example.yaml    DSH 凭据占位
```

`config/settings.psd1`、`config/cordis.patch.current.yml`、`ui/dist/` 已在 `.gitignore` 里。

---

## 构建图形界面

```powershell
python -m pip install pystray pillow pyinstaller
python -m PyInstaller --noconfirm --onedir --noconsole --name WorkBuddyRelayUI `
  --icon ui\app.ico --distpath ui\dist --workpath ui\build --specpath ui ui\wb_bridge_ui.py
```

> 用 **onedir** 而不是 onefile：onefile 在部分机器上会被 Defender 拦成
> `Could not create temporary directory!`，onedir 无需解压即可运行，启动也更快。

界面行为：点 `×` = 最小化到任务栏（不退出）；日志区右上「复制诊断报告」一键生成；
`WorkBuddyRelayUI.exe --diagnose` 不开窗口直接出报告（适合远程排障）。

---

## 换到另一台电脑

不是"拷过去双击就行"。见 [deploy/NEW-MACHINE.md](deploy/NEW-MACHINE.md)：
必须确认 WorkBuddy 已登录、node / python 可用、`settings.psd1` 的 `CodebuddyCli` 指向实际路径。

---

## 排障

| 现象 | 处置 |
|---|---|
| 启动脚本报 401 / 未登录 | token 过期（约 30 天）。打开 WorkBuddy 发一句话 → 重跑启动脚本（自动重扫） |
| DSH 报 `Connection error` | relay 没跑：`wb-relay-status.ps1` 看【2】；或看 `%TEMP%\wb-relay.log` |
| DSH 报 `MISSING_CREDENTIAL` | 缺 `WORKBUDDY_LOCAL_KEY`，见 `config/credentials.example.yaml` |
| 模型只聊天不调工具 | 看日志 `[chat] ... calls=0`；确认 `--tools ""` 生效且 DSH 请求带 tools |
| 模型答得奇怪 / 拒绝配合 | 上游会话历史形成了立场 → WorkBuddy 新建对话后重跑启动脚本 |

更完整的流程图与协议细节见 [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md)，
日常运维与参数调整见 [docs/RUNBOOK.md](docs/RUNBOOK.md)。

---

## License

[MIT](LICENSE) —— 使用前请先读 [SECURITY.md](SECURITY.md) 与上面的免责声明。
