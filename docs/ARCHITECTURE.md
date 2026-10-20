# 架构与协议细节

> 供以后维护/复现用。所有端点与字段都是在本机 WorkBuddy 5.8.3 上实测确认的。

## 1. WorkBuddy 安装形态

```
D:\WorkBuddy\
├─ WorkBuddy.exe                          Electron 桌面端
└─ resources\
   ├─ app.asar                            桌面端主逻辑（含 API 网关常量）
   └─ app.asar.unpacked\
      └─ cli\                             内置 CodeBuddy Code CLI（Node）
         ├─ bin\codebuddy                 入口（node 脚本）
         └─ dist\codebuddy-lite-wb.mjs    WorkBuddy 用的精简 bundle（含 OpenAPI 文档字符串）
```

桌面端启动会话时会拉起：
`WorkBuddy.exe <cli>\bin\codebuddy --serve --session-id <uuid> --permission-mode fullAccess --allowedTools ... --model ...`
并注入 `CODEBUDDY_*` / `WORKBUDDY_*` 环境变量（含 gateway password、QIMEI、VLM token 等）。
**auth token 不在环境里，也不在磁盘上**——只能从进程内存取。

## 2. codebuddy serve 的两套接口

### 2.1 Agent Runs（relay 主要用这条）

```
POST /api/v1/runs
  headers: x-codebuddy-request: 1
  body:    {"id":"msg-x","type":"text","text":"<一条用户消息>","sender":{"id":"..","name":".."}}
  202 ->   {"data":{"runId":"<uuid>","status":"accepted"}}

GET /api/v1/runs/{runId}/stream        (Accept: text/event-stream)
  event: message
  data: {"version":"1.0","replyTo":"msg-x","status":"completed",
         "content":{"markdown":"..."},"agent":{"sessionId":"...","toolCalls":[]}}
  event: done
  data: {}
```

要点：**一次只能带一条文本**，所以 relay 把 system/历史/工具清单打包成 JSON 塞进这条文本。

### 2.2 ACP（Agent Client Protocol，JSON-RPC over HTTP + SSE）

```
POST /api/v1/acp/connect           -> {connectionId, sessionToken}
POST /api/v1/acp                   (头: acp-connection-id / acp-session-token)
  initialize         -> {protocolVersion, agentCapabilities, authMethods}
  session/new        -> {sessionId, models, modes, configOptions}
  session/load | session/resume
  session/prompt     -> SSE: session/update {sessionUpdate: agent_message_chunk | tool_call | ...}
  session/cancel
  session/set_model     {sessionId, modelId}
  session/set_mode      {sessionId, modeId}
  session/set_config_option
  authenticate          {methodId: iOA|external|internal|selfhosted}
```

注意：
- 必须先 `initialize`，再在同一 `acp-connection-id` 上发 `session/*`，否则 `Bad Request: Server not initialized`
- `session/new` **不支持** 自定义 system prompt
- permission mode（plan / default / dontAsk）**拦不住**工具执行（实测 plan 仍能写文件、default 仍能读文件）

### 2.3 其他端

`/api/v1/auth/status`、`/api/v1/info`、`/api/v1/health`、`/api/v1/sessions`、`/api/v1/fs/*`、
`/api/v1/pty/*`、`/api/v1/jobs/*`、`/api/v1/plugins/*`；`/api/openapi.json` 在
`CODEBUDDY_GATEWAY_DISABLE_API_DOCS=1` 时返回 404，但 bundle 内嵌了等价文档字符串。

## 3. CLI 的关键启动参数（硬解模式用）

| 参数 | 作用 |
|---|---|
| `--serve --port N --host 127.0.0.1` | 起 HTTP 服务 |
| `--auth none` | 本地免鉴权（我们只在 127.0.0.1 用） |
| `--tools ""` | 禁用全部内置工具（空字符串） |
| `--system-prompt-file <path>` | 用文件内容替换系统提示词 |
| `--system-prompt` / `--append-system-prompt` | 内联版（命令行长度受限，长文本用 file） |
| `--permission-mode default` | 工具需审批（配合无工具场景更保守） |

环境变量：`CODEBUDDY_FORCE_LITE_WB_BUNDLE=1`（用 unpacked 里的 lite-wb bundle，否则找不到 `../dist/codebuddy`）、
`CODEBUDDY_AUTH_TOKEN`（Bearer JWT，CLI 认这个，错误信息里显示 `auth-type:custom-token`）。

## 4. relay 的转换规则

### 4.1 入站（OpenAI → 数据包）

```
messages[]                       →  <data>{
  role=system   → context            "context": "<DSH system>",
  role=user     → input/history      "tools":   [{name, description, parameters}],
  role=assistant(tool_calls)         "history": [{from, text}],
  role=tool     → <tool_result>      "input":   "<最后一条 user>"
                                 }</data>
```

- `systemMode=full`：context 原样全送（自建 serve 场景）
- `systemMode=tail`：过滤敏感段 + 只留尾部 N 字（旧模式场景，避免上游把 DSH 人设当"夹带设定"）
- 图片（`image_url`）→ 降级为文字占位「附带了 N 张图片，像素不可见」

### 4.2 出站（上游文本 → OpenAI）

- 解析 `<tool_call>{"name":..,"arguments":{..}}</tool_call>`（也兼容 ```json {"tool_calls":[...]}```）
- 命中 → 流式发 `tool_calls` delta（index/id/name/arguments 一次给全）+ `finish_reason=tool_calls`
- 未命中 → 按 24 字切块伪流式发 content + `finish_reason=stop`
- 上游 429 → 直接回 429 并带明确文案（不伪装成超时）

## 5. 为什么不自己在会话里改 system

`session/new` 没有 system 字段；`set_config_option` 只覆盖 mode/model/thought/context/sandbox/multitask。
所以"DSH 提示词当 system 用"只能靠**换一个我们自己的 serve 实例**，在启动时用
`--system-prompt-file` 指定"执行代理 + 身份来自 context"的引导词。
