# 换到另一台电脑：部署清单

> 结论先说：**拷过去之后要跑一次 `一键安装.cmd`，不是直接双击 exe 就行**。
> 仓库里不含 exe 与桌面快捷方式（都在安装时现生成），而且能不能跑取决于下面 6 个前置条件，其中 3 个必须人工确认。

## 一、判定表：什么情况下能跑

| 前置条件 | 缺了会怎样 | 怎么自查（PowerShell） |
|---|---|---|
| Windows 10/11 | 完全不可用（依赖计划任务 + PEB 读取） | `$PSVersionTable.PSVersion` |
| **WorkBuddy 已安装 + 已登录 + 发过一句话** | 取不到 token，serve 起不来 | WorkBuddy 界面能看到对话即可 |
| **Node.js**（或 WorkBuddy 自带） | serve 起不来 | `Get-Command node`；缺失时脚本会自动用 `%USERPROFILE%\.workbuddy\binaries\node\versions\*\node.exe` |
| **Python 3.8+**（要 `pythonw.exe`） | relay 起不来 | `Get-Command pythonw` 或看 `%LOCALAPPDATA%\Programs\Python\Python3*` |
| 项目目录 + `settings.psd1` 里的 CLI 路径正确 | 找不到 codebuddy | 该路径下 `codebuddy` 文件存在 |
| 端口 8787 / 8791 没被占 | 启动失败 | `Get-NetTCPConnection -State Listen -LocalPort 8787,8791` |
| 这台机器也装了 DSH 并配了 provider | 工具跑起来了但 DSH 不会用 | DSH 模型下拉里能看到「脑力·」系列 |

> 网络：需要能访问 `www.workbuddy.cn`（公司代理可能拦）。
> 杀软：会看到"读取其他进程内存"告警，这是取 token 的必要动作，加白即可。

## 二、三步部署

### 第 1 步：拷目录 + 改一行配置

把整个 `workbuddy-dsh-bridge\` 拷到目标机任意位置（路径别带空格），然后**只改这一个文件**：

`config\settings.psd1`

```powershell
@{
    CodebuddyCli  = '<WorkBuddy安装目录>\resources\app.asar.unpacked\cli\bin\codebuddy'
    PythonExe     = ''      # 留空自动探测
    NodeExe       = ''      # 留空自动探测
    ServePort     = 8791
    RelayPort     = 8787
    DshHome       = '<目标机的 .dsh 目录>'
    RuntimeDir    = 'C:\temp'
}
```

`CodebuddyCli` 的默认值写的是 `D:\WorkBuddy\...`，**别的机器十有八九不是这个路径**（常见在 `C:\Program Files\WorkBuddy`、`%LOCALAPPDATA%\Programs\WorkBuddy`）。
不确定就搜一下：

```powershell
Get-ChildItem 'C:\','D:\' -Recurse -Filter codebuddy -ErrorAction SilentlyContinue |
  Where-Object { $_.FullName -like '*app.asar.unpacked\cli\bin\codebuddy' } |
  Select-Object -First 3 FullName
```

### 第 2 步：让 WorkBuddy 处于"可被取 token"的状态

打开 WorkBuddy → 确认已登录 → **随便发一句话**（或新建一个对话）。
这一步是为了让 `codebuddy --serve` 进程活着，token 就在它的内存里。

> 不要把旧机器的 `C:\temp\wb-jwt.txt` 拷过来 —— token 绑账号会话，新机器重扫更干净。

### 第 3 步：跑一次安装 → 双击桌面图标 → 点「启动 / 修复」

**先在项目根双击 `一键安装.cmd`**（探测 CLI 路径 → 写配置 → 打包 exe → 建桌面快捷方式），之后双击桌面「WorkBuddy中转工具」即可。

> 仓库里**不含** exe 与桌面快捷方式（`.gitignore` 排除了 `ui/dist/`），`ui\dist\WorkBuddyRelayUI\WorkBuddyRelayUI.exe` 是安装时现生成的。

看到三盏灯变绿 + 日志里出现 `自测通过 / 工具自测：finish=tool_calls` 就算成功。
失败的话点日志区右上「**复制诊断报告**」，把内容贴出来即可定位。

## 三、目标机还要配 DSH（否则工具白跑）

这个工具只是"给 DSH 提供一个 OpenAI 兼容的模型来源"，它自己不会让 DSH 多出模型。目标机的 DSH 需要：

1. `cordis.patch.yml` 里加 `workbuddy` provider 段（照抄本项目的 `config\cordis.patch.current.yml`）
2. `.credentials.yaml` 的 `refs:` 下加一行 `WORKBUDDY_LOCAL_KEY: local-relay-placeholder`
3. 重启 DSH 桌面端

如果目标机的 relay 端口不是 8787，第 1 步里的 `baseURL` 也要跟着改。

## 四、常见失败与处置

| 现象 | 原因 | 处置 |
|---|---|---|
| 日志 `找不到 codebuddy CLI` | 路径不对 | 改 `settings.psd1` 的 `CodebuddyCli` |
| 日志 `找不到 node.exe` | 没装 Node.js 且 WorkBuddy 太新/太旧没有自带 | 装 Node.js 18+，或设 `NodeExe` |
| 日志 `找不到 pythonw.exe` | 没装 Python | 装 Python 3.x（勾选 Add to PATH） |
| 日志 `需要 WorkBuddy 在运行` | WorkBuddy 没开 / 没登录 | 打开并发一句话 |
| `上游未登录 / 401` | token 过期（约 30 天） | 打开 WorkBuddy 发一句话 → 重新点启动（自动重扫） |
| DSH 报 `Connection error` | relay 没跑 | 双击桌面「WorkBuddy中转工具」点启动；或看 `C:\temp\wb-relay.log` |
| DSH 报 `MISSING_CREDENTIAL` | 缺 `WORKBUDDY_LOCAL_KEY` | 见第三节第 2 步 |
| 端口被占 | 8787/8791 冲突 | 改 `settings.psd1` 两个端口 + DSH 的 `baseURL` |

## 五、换机后想"少踩坑"的建议

1. **先在目标机只跑诊断**：`WorkBuddyRelayUI.exe --diagnose`，不开窗口，直接告诉你哪一项没就绪。
2. **别从备份目录直接启动**：备份的脚本会重新注册计划任务指向备份路径，等于把生产切到副本。备份是冷备。
3. **WorkBuddy 大版本升级后**先验证 CLI 参数还在：
   ```powershell
   node "<CLI路径>" --help | Select-String 'serve|tools|system-prompt'
   ```
   参数变了就改 `scripts\wb-clean-start.ps1` 里生成 `$serveLines` 的那段。
