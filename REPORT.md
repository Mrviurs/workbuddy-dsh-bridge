# 报告：WorkBuddy → DeepSeek Harness 模型桥

- 项目名：`workbuddy-dsh-bridge`
- 位置：`<PROJECT_ROOT>`
- 目标机：本机（Windows / PowerShell 5.1 / WorkBuddy 5.8.3 / DSH 桌面版）
- 定稿时间：2026-10-20 22:0x

---

## 1. 交付物

| 类别 | 文件 | 作用 |
|---|---|---|
| 网关 | `relay/workbuddy-openai-relay.py` | OpenAI ⇄ WorkBuddy（runs + ACP）双向转换，含工具调用 |
| 启动 | `scripts/wb-clean-start.ps1` | 取 token → 起自建 serve(8791) → 起 relay(8787) → 身份/工具双自测 |
| 巡检 | `scripts/wb-relay-status.ps1` | serve / relay / token / DSH 配置 四面板 |
| 停止 | `scripts/wb-relay-stop.ps1` | 停两个计划任务 + 释放两个端口 |
| 取凭据 | `scripts/wb-scan-token.ps1` | 从运行中 WorkBuddy 进程内存扫 JWT |
| 配置 | `config/settings.psd1` | **换机只需改这里**（CLI 路径 / python / 端口） |
| 配置 | `config/wb-sysprompt.txt` | 自建 serve 的 system prompt 模板 |
| 配置 | `config/cordis.patch.current.yml` | 本机 DSH patch 快照（workbuddy provider 段） |
| 桌面 | `desktop/*.cmd` × 4 | 项目内相对路径运行；`install.ps1` 会在桌面创建快捷方式 |

---

## 2. 架构

```
DSH 桌面端
  │  provider=workbuddy, baseURL=http://127.0.0.1:8787/v1, api=openai-completions
  ▼
relay (pythonw, 8787)                       ← 计划任务 WorkBuddyRelay
  │  · 把 system+messages+tools 打包成 <data> JSON
  │  · 解析 <tool_call> → OpenAI tool_calls（含并行、多轮回填）
  ▼
自建 serve (node, 8791)                     ← 计划任务 WorkBuddyCleanServe
  │  codebuddy --serve --auth none --tools "" --system-prompt-file ...
  │  Authorization: Bearer <账号 JWT>
  ▼
腾讯网关 www.workbuddy.cn（账号额度）
```

关键设计取舍：

| 决策 | 原因 |
|---|---|
| 不用 WorkBuddy 自己的 serve，自己起一个 | 它 `--permission-mode fullAccess` 且人格固定，DSH 提示词压不住 |
| `--tools ""` | 让上游彻底没手，工具只能交给 DSH 执行（不再绕过沙箱） |
| `--system-prompt-file` + "身份来自 context" 的引导语 | 让 DSH 的 system 事实上成为 system，同时保留每轮可变的动态部分 |
| 用计划任务而不是 Start-Process | 前者父进程是 svchost，退出 DSH / 关窗口都不会连带杀死 |

---

## 3. 三个技术关卡（都已实测通过）

### 3.1 凭据：CLI 独立启动必须自带 token

- 试过 4 种配置目录组合（`CODEBUDDY_CONFIG_DIR` / `WORKBUDDY_CONFIG_DIR` / `CODEBUDDY_HOST` / `--settings`）→ 全部 `Authentication required`，说明凭据不在盘上。
- 抓包路线排除：serve 出站走 `198.18.0.x → 198.18.0.80:443`（系统代理 fake-IP），不存在 WorkBuddy 内部 MITM 注入。
- **解法**：从运行中的 serve 进程内存扫描（`VirtualQueryEx` + `ReadProcessMemory`，498MB / 1196 个区域，几秒）；扫到的 JWT 交给环境变量 `CODEBUDDY_AUTH_TOKEN`。
- 踩过的坑：第一次正则上限 300 字符，把 1323 字符的 JWT 截断了 → `401 (token-length:300)`。放宽到 4000 并补 `=+/` 后成功。

### 3.2 token 传递：cmd 的 1023 字符天花板

`set /p VAR=<file` 会把环境变量截断到 1023 字符 → 换成 PowerShell 脚本读文件再设 `$env:`，
并用**单字符串** `-ArgumentList` 传参（否则 `--tools ""` 的空引号会被 PowerShell 吃掉）。

### 3.3 身份：DSH 提示词如何真正生效

自建 serve 的 system prompt 写成"**执行代理，身份来自 data.context**"，于是：

- DSH 的 system 每轮作为 `context` 注入 → 模型照它建立身份（实测：`我是测试员甲。` / `我是 Little Code Sauce，YG 的女朋友。`）
- 上游不再有 WorkBuddy 助手的自我认知，也不会拒绝"你是 X"这类设定

---

## 4. 实测证据（2026-10-20）

```
[凭据]  JWT len=1323  exp=2026-11-17 21:14:39  iss=https://www.workbuddy.cn/auth/realms/copilot
[启动]  自建 serve 就绪：port=8791  authEnabled=False  authenticated=True
[启动]  relay 就绪：http://127.0.0.1:8787/v1 -> http://127.0.0.1:8791  systemMode=full
[身份]  身份自测：我是测试员甲。
[工具]  工具自测：finish=tool_calls -> read{"file_path": "C:/temp/wb-relay-config.json"}
[选择]  5 个工具里问"找 .json 文件" → 正确选 glob；双工具并行 → index 0 read / index 1 glob
[回填]  回填 <tool_result> 后 finish=stop 并直接答出取值，不重复调用
[无手]  要求读文件 → "ModelBehaviorError: Tool Read not found in agent cli"（工具确实被禁）
```

---

## 5. 与原生路由的差距（不可消除）

| 项 | 原生 deepseek 路由 | 本桥 |
|---|---|---|
| 工具调用 | ✅ | ✅（含并行 / 多轮回填） |
| 沙箱与审批 | ✅ 全覆盖 | ✅ 全覆盖（上游无工具） |
| 图片输入 | ✅ | ❌ 只传文本，图片降级为占位说明 |
| reasoning 过程 | ✅ | ❌ 只有最终文本与工具调用 |
| token 成本 | 标准 | 偏高：`systemMode=full` 每轮送完整 system |
| 稳定性 | 官方直连 | 依赖 WorkBuddy CLI 内部实现（版本升级需复查） |

---

## 6. 换到别的电脑：预估

### 6.1 结论

| 场景 | 一次成功的概率 | 说明 |
|---|---|---|
| 同版本 WorkBuddy(5.8.3) + 同账号已登录 + 有 Python 3.x | **≈ 85%** | 改 `settings.psd1` 里 1~2 行即可 |
| WorkBuddy 升级到大版本（6.x 之类） | **≈ 50%** | CLI 参数或 API 路径可能变，需重新侦察（脚本里有两处可调） |
| 别的账号 | ≈ 70% | 需在目标机登录 WorkBuddy 并重扫 token；额度是目标账号的 |
| 没装 WorkBuddy / 没登录 | **0%** | token 无从取得，整套失效 |
| 非 Windows | 0% | 依赖 Windows 计划任务、PEB 读取、PowerShell |

### 6.2 必须改的地方（换机清单）

1. `config/settings.psd1`：
   - `CodebuddyCli` = 目标机 `<WorkBuddy 安装目录>\resources\app.asar.unpacked\cli\bin\codebuddy`
   - `PythonExe` 留空则自动探测（`%LOCALAPPDATA%\Programs\Python\Python311\pythonw.exe` 或 PATH）
   - 端口冲突时改 `ServePort` / `RelayPort`
2. DSH 侧：把 `config/cordis.patch.current.yml` 里的 `workbuddy` provider 段与
   `.credentials.yaml` 的 `WORKBUDDY_LOCAL_KEY` 加到目标机的 profile，然后重启 DSH。
3. 目标机上跑一次 `一键安装.cmd`：自动探测 CLI 路径、生成 settings.psd1、重建桌面快捷方式。

### 6.3 换机时会踩的坑（按发生概率排序）

| 概率 | 坑 | 处置 |
|---|---|---|
| 高 | WorkBuddy 不在 `D:\WorkBuddy` | 改 `settings.psd1` 的 `CodebuddyCli` |
| 高 | 没装 Python / 不是 3.11 | 装 Python 3.9+ 或把 `PythonExe` 指到现有解释器 |
| 中 | 端口 8787/8791 被占 | 改 `settings.psd1`，并同步改 DSH 的 baseURL |
| 中 | 计划任务创建被组策略拦 | 以管理员运行一次，或改用手动 `Start-Process`（牺牲持久性） |
| 中 | 公司网络禁 `www.workbuddy.cn` | 无解，需放行 |
| 中 | 杀软告警"读取其他进程内存" | 属预期行为（同用户读自己的进程），加白即可 |
| 低 | PowerShell 执行策略限制 | 脚本已用 `-ExecutionPolicy Bypass` 调用 |
| 低 | 中文路径 / 无 BOM 导致脚本解析失败 | 项目内 `.ps1` 均为 UTF-8 BOM，请勿另存为 ANSI |

### 6.4 迁移建议

- **不要把 `C:\temp\wb-jwt.txt` 拷到新机器**：token 绑账号会话，直接在新机器重扫更干净（启动脚本自动做）。
- 新机器第一次运行前，先在 WorkBuddy 里发一句话（确保 serve 进程在跑，才有内存可扫）。
- 若目标机的 WorkBuddy 版本与本机不同，先只跑 `scripts/wb-scan-token.ps1` 验证能否扫到 JWT，
  再跑完整启动——这样最坏情况只损失几分钟。

---

## 7. 风险清单

| 风险 | 影响 | 缓解 |
|---|---|---|
| `wb-jwt.txt` 泄漏 | 等同账号凭据被盗用（约 30 天） | 仅本机、勿提交、勿截图；过期自动失效 |
| WorkBuddy 升级 | 桥失效 | 保留旧模式脚本作 fallback；必要时重新侦察 API |
| 账号风控 / 限流 | 429 RATE_LIMITED | relay 已把 429 翻译成明确提示；等冷却或切原生路由 |
| 额度消耗 | 按 credits 计费 | 默认模型仍是原生；只在「脑力」任务时切过来 |
| 端口暴露 | `--auth none` 无鉴权 | 绑定 127.0.0.1，不要改 `--host 0.0.0.0` |
| 上游模型人格残留 | 偶发"AI 助手"口吻 | 已通过 `--system-prompt-file` 压制；如需更狠可调 `systemMode` |

---

## 8. 后续可做（未做）

1. **token 自动续期**：JWT 带 `offline_access`，可用 refresh_token 换新 access_token，避免每 30 天重扫。
2. **图片支持**：runs 接口只收文本，需要改用 ACP 的 `image` 内容块，并把 DSH 的 base64 图片塞进去。
3. **reasoning 回传**：上游 `session/update` 里有 thinking 事件，可映射成 OpenAI 的 `reasoning_content`。
4. **旧模式退役**：待硬解在目标机稳定后，删掉 `wb-relay-start.ps1` 与 `wb-read-env.ps1`。
