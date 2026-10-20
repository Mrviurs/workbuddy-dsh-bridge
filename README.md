# workbuddy-dsh-bridge

[![License: Personal Free · Commercial By Permission](https://img.shields.io/badge/license-personal%20free%20%C2%B7%20commercial%20by%20permission-orange.svg)](LICENSE)
[![OSI Open Source](https://img.shields.io/badge/OSI%20open%20source-no-red.svg)](#license)
[![Platform](https://img.shields.io/badge/platform-Windows%2010%2F11-0078D4)](#)
[![PowerShell](https://img.shields.io/badge/PowerShell-5.1%2B-5391FE)](#)
[![Python](https://img.shields.io/badge/Python-3.8%2B-3776AB)](#)

把 **WorkBuddy**（CodeBuddy 桌面端）账号里的模型，接成 **DeepSeek Harness** 的一个 OpenAI 兼容 provider。

做到三件原本做不到的事：

1. **DSH 的提示词真正作为 system 生效** —— 不是塞进 user 消息当"资料"
2. **上游零工具权限** —— `--tools ""`，工具只能交给 DSH 执行，不再绕过沙箱与审批
3. **工具调用双向互通** —— `<tool_call>` ⇄ OpenAI `tool_calls`，支持并行、多轮回填

> 原理一句话：WorkBuddy 安装目录里自带 `codebuddy` CLI。用它自己的账号 token
> 起一个**我们控制的** `--serve` 实例，再用一个 Python 网关翻成 OpenAI 接口。

---

## 免责声明（必读）

> 完整版：[DISCLAIMER.md](DISCLAIMER.md)（中文） · [DISCLAIMER.en.md](DISCLAIMER.en.md) (English)
> 下载、运行或修改本项目，即视为接受全部条款。本文档不构成法律意见。

**一、与官方无关**
本项目是独立的个人技术项目，**不是** 腾讯 / WorkBuddy / CodeBuddy 的官方产品或合作项目，
**不是** 深度求索 / DeepSeek / DSH 的官方集成，**未获**任何授权、认可或支持。
所有商标归其各自所有者。

**二、它到底做了什么**
① 读取你**自己启动的** WorkBuddy 进程内存，取出该账号的 access token；
② 写入本地 `C:\temp\wb-jwt.txt`（明文）；③ 用该凭据启动 WorkBuddy 自带的
`codebuddy --serve`（仅监听 `127.0.0.1`）；④ 把你的对话转发到 `www.workbuddy.cn`
——**与你直接使用 WorkBuddy 时数据流向相同**；⑤ 注册两个开机自启任务。
**不收集、不上报、不回传任何数据**，可断网审计源码验证。

**三、你接受的风险**
- 账号可能被限流 / 降级 / 暂停 / 封禁，额度可能异常消耗——**作者无法干预、不承担责任**；
- 依赖上游**未公开内部接口**，对方任意一次更新都可能让它失效，**作者没有修复义务**；
- `wb-jwt.txt` 里的 token **约等于账号密码**，泄露后果自负；
- 本软件会修改 DSH 配置并注册计划任务，配置混乱 / 数据丢失风险自负。

**四、商用与禁止用途**
- ✅ **个人非商业使用**：免费，不需要申请
- 🤝 **商业使用**：**允许，但需事先取得书面授权** —— 开个 issue 标题写 `[Commercial License]`，说明你是谁、要做什么、多大规模
- 🚫 **授权也不覆盖**：转售 / 出租 / 代充 / 售卖访问权、做成"中转站"对外供 API、批量注册 / 多账号池 / 代他人提取凭据、帮助他人绕过官方付费、移除版权许可声明后分发、任何违法或违反上游条款的用途

分两类看清楚：**"用这个软件做商业"可以谈；"滥用上游服务"给多少钱都不行。**

**五、担保与责任**
按"AS IS"提供，无任何担保；作者不承担间接 / 附带 / 后果性损害（含利润、数据、凭据、账号、额度损失）；
**你就因自己使用而产生的第三方索赔对作者进行赔偿并使其免责**。

**六、合规是你的责任**
需自行确认并遵守 WorkBuddy / DeepSeek 的服务条款、你所在地的法律法规、以及你所在单位的安全制度。
**作者不替你判断边界**——按下"启动"的那一刻，这个判断就由你做出了。

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

```bash
git clone git@github.com:Mrviurs/workbuddy-dsh-bridge.git
cd workbuddy-dsh-bridge
```


### 前置条件

- Windows 10/11
- **WorkBuddy 已安装并登录**，且在界面里**至少发过一句话**（token 从它的 serve 进程内存取）
- **Node.js 18+**（缺失时会自动用 WorkBuddy 自带的 `~/.workbuddy/binaries/node/versions/*/node.exe`）
- **Python 3.8+**（要 `pythonw.exe`，relay 用它跑）
- DeepSeek Harness（否则桥起来了也没人用）

### 三步

> **⚠️ 第 0 步必做**：仓库里**没有** `config/settings.psd1`（它是本机配置，已被 gitignore）。
> 首次运行前必须从模板复制一份，并把 `CodebuddyCli` 改成你自己的 WorkBuddy 安装路径，
> 否则启动脚本会报「CodebuddyCli 还是占位符」。

```powershell
copy config\settings.example.psd1 config\settings.psd1
notepad config\settings.psd1
# 只改这一行：CodebuddyCli = '<你的WorkBuddy安装目录>\resources\app.asar.unpacked\cli\bin\codebuddy'
```

> 不确定路径？搜一下：
> `Get-ChildItem C:\,D:\ -Recurse -Filter codebuddy -ErrorAction SilentlyContinue | Where-Object { $_.FullName -like '*app.asar.unpacked\cli\bin\codebuddy' }`

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

## 使用文档

| 文档 | 给谁看 |
|---|---|
| **[傻瓜手册（中文）](docs/GUIDE.zh-CN.md)** | 不想碰命令行的人。照着点，5 分钟上手 |
| **[Idiot-Proof Guide (English)](docs/GUIDE.md)** | Same thing, in English |
| [运维手册](docs/RUNBOOK.md) | 日常排障、调参、换机 |
| [协议细节](docs/ARCHITECTURE.md) | 想改代码 / 上游升级后要修 |
| [换机部署清单](deploy/NEW-MACHINE.md) | 要在另一台电脑上跑 |
| [实测报告](REPORT.md) | 架构、证据、能力边界 |
| **[免责声明](DISCLAIMER.md) / [Disclaimer](DISCLAIMER.en.md)** | 使用前必读：风险、禁止用途、责任划分 |

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
| `git push` 报 `Permission denied (publickey)` + 乱码路径 | 中文用户名撞上 Git 自带 MSYS ssh，改用 Windows OpenSSH：`git config --global core.sshCommand "C:/Windows/System32/OpenSSH/ssh.exe"`（详见 docs/RUNBOOK.md） |

更完整的流程图与协议细节见 [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md)，
日常运维与参数调整见 [docs/RUNBOOK.md](docs/RUNBOOK.md)。

---

## License

**[Personal-Use & Commercial-By-Permission License v1.1](LICENSE)** —— 双许可模式：

| 用途 | 是否需要申请 |
|---|---|
| 个人 / 非商业使用（读、改、跑） | **免费，不需要申请** |
| 商业使用（企业内部流程、付费服务、商业产品集成） | **需事先取得书面授权** |

**怎么申请商用授权**：开一个 issue，标题写 `[Commercial License]`，内容说明：你是谁 / 打算做什么 / 大概什么规模。看到会回。
（沉默不等于同意 —— 没收到明确答复之前，商业使用仍未授权。）

> 因为商用不是自动授予，所以本项目**不属于 OSI 定义的"开源软件"**，
> 准确说法是 **source-available（源码可用）+ 双许可**。

使用前请先读 [DISCLAIMER.md](DISCLAIMER.md) 与 [SECURITY.md](SECURITY.md)。

---

仓库：<https://github.com/Mrviurs/workbuddy-dsh-bridge>
