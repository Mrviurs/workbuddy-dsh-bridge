# wb-relay-start.ps1  —— 由桌面「启动WorkBuddy中转.cmd」调用
# 作用：把本机 WorkBuddy 的 codebuddy 服务重新桥接成 OpenAI 兼容接口（127.0.0.1:8787）
#
# 关键设计：relay 由 Windows 计划任务（WorkBuddyRelay）托管，
#   父进程是任务计划程序服务，不属于任何终端会话，
#   所以关闭 DSH / 关闭这个窗口 / 注销当前 shell 都不会把 relay 一起带走。
#   之前用 Start-Process 起的进程会被 DSH 的作业对象连带杀死，这就是「Connection error」的原因。

param([switch]$SkipSelfTest, [ValidateSet("tail","full","none")][string]$SystemMode = "tail")


# 运行时目录（本机固定 C:\temp；不存在时自动创建，避免首次运行报错）
if (-not (Test-Path 'C:\temp')) { New-Item -ItemType Directory -Force 'C:\temp' | Out-Null }
$ErrorActionPreference = "Continue"
$root = Split-Path -Parent $PSScriptRoot
$readEnv = Join-Path $PSScriptRoot 'wb-read-env.ps1'
$relayPy = Join-Path $root 'relay\workbuddy-openai-relay.py'
$logFile = 'C:\temp\wb-relay.log'
$cfgFile = 'C:\temp\wb-relay-config.json'
$envFile = 'C:\temp\wb-cli-env.txt'
$taskName = 'WorkBuddyRelay'
$Port = 8787

function Ok($t)   { Write-Host "  [OK]   $t" -ForegroundColor Green }
function Warn($t) { Write-Host "  [WARN] $t" -ForegroundColor Yellow }
function Bad($t)  { Write-Host "  [FAIL] $t" -ForegroundColor Red }

Write-Host ""
Write-Host "=== WorkBuddy -> DeepSeek Harness 中转启动器 ===" -ForegroundColor Cyan
Write-Host ""

# ---------- 0. pythonw（无控制台窗口的 python）----------
$pyDir = "$env:LOCALAPPDATA\Programs\Python\Python311"
$pythonW = Join-Path $pyDir 'pythonw.exe'
if (-not (Test-Path $pythonW)) {
  $py = (Get-Command python -ErrorAction SilentlyContinue).Source
  if ($py) { $pythonW = Join-Path (Split-Path $py -Parent) 'pythonw.exe' }
}
if (-not (Test-Path $pythonW)) { $pythonW = (Get-Command pythonw -ErrorAction SilentlyContinue).Source }
if (-not $pythonW -or -not (Test-Path $pythonW)) { Bad "找不到 pythonw.exe"; exit 1 }
Ok "pythonw: $pythonW"

# ---------- 1. 停掉旧 relay（端口 + 计划任务）----------
& schtasks /end /tn $taskName 2>&1 | Out-Null
$old = Get-NetTCPConnection -State Listen -LocalPort $Port -ErrorAction SilentlyContinue | Select-Object -First 1
if ($old) {
  try { Stop-Process -Id $old.OwningProcess -Force -ErrorAction Stop; Start-Sleep -Milliseconds 800; Ok "已停止旧 relay (pid $($old.OwningProcess))" }
  catch { Warn "旧 relay 停止失败：$($_.Exception.Message)" }
} else { Ok "没有旧 relay 占用 $Port" }

# ---------- 2. 找最新的 codebuddy --serve 进程 ----------
$serves = Get-CimInstance Win32_Process -Filter "Name='WorkBuddy.exe'" |
          Where-Object { $_.CommandLine -match 'cli\\bin\\codebuddy' -and $_.CommandLine -match '--serve' } |
          Sort-Object CreationDate -Descending
if (-not $serves) {
  Bad "没找到 codebuddy --serve 进程"
  Write-Host ""
  Write-Host "  处理办法：打开 WorkBuddy，随便发一句话（或新建一个对话），让它把 serve 拉起来，再重新双击本脚本。" -ForegroundColor Yellow
  exit 1
}
$proc = $serves | Select-Object -First 1
$sid = if ($proc.CommandLine -match '--session-id[= ]([0-9a-fA-F\-]{8,})') { $matches[1] } else { "(未知)" }
Ok "serve 进程 pid=$($proc.ProcessId)  会话=$sid"
if ($serves.Count -gt 1) { Warn "另有 $($serves.Count - 1) 个旧 serve 进程（旧会话），已按最新一个绑定" }

# ---------- 3. 读网关密码 ----------
& $readEnv -ProcessId $proc.ProcessId 6>$null | Out-Null
if (-not (Test-Path $envFile)) { Bad "读取进程环境失败（wb-cli-env.txt 未生成）"; exit 1 }
$gw = (Get-Content $envFile | Where-Object { $_ -match '^CODEBUDDY_GATEWAY_PASSWORD=' }) -replace '^[^=]+=',''
if (-not $gw) { Bad "拿不到 CODEBUDDY_GATEWAY_PASSWORD"; exit 1 }
Ok "网关密码已读取 (len=$($gw.Length))"

# ---------- 4. 端口 + 登录态 ----------
$listen = Get-NetTCPConnection -State Listen -OwningProcess $proc.ProcessId -ErrorAction SilentlyContinue | Select-Object -First 1
if (-not $listen) { Bad "拿不到 serve 监听端口"; exit 1 }
$base = "http://127.0.0.1:$($listen.LocalPort)"
Ok "上游地址 $base"
try {
  $st = Invoke-RestMethod -Uri "$base/api/v1/auth/status" -Headers @{ Authorization = "Bearer $gw" } -TimeoutSec 10
  if ($st.authenticated) { Ok "上游已登录（authenticated=true）" } else { Warn "上游未登录：先在 WorkBuddy 里发一句话再试" }
} catch { Bad "探测上游失败：$($_.Exception.Message)"; exit 1 }

# ---------- 5. 会话标题 ----------
try {
  $ss = Invoke-RestMethod -Uri "$base/api/v1/sessions" -Headers @{ Authorization = "Bearer $gw" } -TimeoutSec 10
  $cur = $ss.data.sessions | Where-Object { $_.id -eq $sid } | Select-Object -First 1
  if ($cur) { Ok "绑定会话：""$($cur.name)""  (消息数 $($cur.messageCount))" }
} catch { }

# ---------- 6. 写配置 + 注册计划任务 ----------
New-Item -ItemType Directory -Force C:\temp | Out-Null
$cfg = [ordered]@{ base = $base; password = $gw; port = $Port; systemMode = $SystemMode } | ConvertTo-Json -Compress
[System.IO.File]::WriteAllText($cfgFile, $cfg, (New-Object System.Text.UTF8Encoding($false)))
Ok "配置已写入 $cfgFile（systemMode=$SystemMode）"

$tr = "`"$pythonW`" `"$relayPy`" --log `"$logFile`""
& schtasks /create /tn $taskName /tr $tr /sc once /st 23:59 /f 2>&1 | Out-Null
if ($LASTEXITCODE -ne 0) {
  Bad "注册计划任务失败（schtasks 返回 $LASTEXITCODE）"
  Write-Host "  可以退回到前台模式手工跑：" -ForegroundColor Yellow
  Write-Host "  `"$pythonW`" `"$relayPy`" --log `"$logFile`"" -ForegroundColor DarkGray
  exit 1
}
Ok "计划任务 [$taskName] 已注册"

if (Test-Path $logFile) { Remove-Item $logFile -Force -ErrorAction SilentlyContinue }
& schtasks /run /tn $taskName 2>&1 | Out-Null
if ($LASTEXITCODE -ne 0) { Bad "启动计划任务失败（schtasks 返回 $LASTEXITCODE）"; exit 1 }

# ---------- 7. 等 relay 就绪 ----------
$health = $null
for ($i = 0; $i -lt 25; $i++) {
  Start-Sleep -Milliseconds 800
  try { $health = Invoke-RestMethod "http://127.0.0.1:$Port/health" -TimeoutSec 3; break } catch { }
}
if (-not $health) {
  Bad "relay 25 秒内没起来，日志：$logFile"
  if (Test-Path $logFile) { Get-Content $logFile -Tail 20 }
  Write-Host ""
  Write-Host "  常见原因：计划任务被安全软件拦、pythonw 被杀、端口被占。" -ForegroundColor Yellow
  exit 1
}
$rl = Get-NetTCPConnection -State Listen -LocalPort $Port -ErrorAction SilentlyContinue | Select-Object -First 1
Ok "relay 已就绪 (pid $($rl.OwningProcess)) -> http://127.0.0.1:$Port/v1  当前模型 $($health.model)"
Ok "进程由计划任务托管，关闭本窗口 / 退出 DSH 都不会停"

# ---------- 8. 自测 ----------
if (-not $SkipSelfTest) {
  Write-Host "  正在自测一次真实对话（消耗极少额度）…" -ForegroundColor DarkGray
  $body = '{"model":"wb-deepseek-flash","messages":[{"role":"user","content":"只回复两个字：通了"}]}'
  try {
    $r = Invoke-RestMethod -Method Post -Uri "http://127.0.0.1:$Port/v1/chat/completions" -ContentType 'application/json; charset=utf-8' -Body ([System.Text.Encoding]::UTF8.GetBytes($body)) -TimeoutSec 240
    Ok "自测通过，模型回复：$($r.choices[0].message.content)"
  } catch { Warn "自测失败（relay 仍在跑，DSH 首次请求会重试）：$($_.Exception.Message)" }
}

Write-Host ""
Write-Host "全部就绪 —— 回到 DeepSeek Harness，在模型下拉里选 WorkBuddy 系列模型即可。" -ForegroundColor Green
Write-Host "代理地址: http://127.0.0.1:$Port/v1   |   upstream: $base" -ForegroundColor DarkGray
Write-Host ""
