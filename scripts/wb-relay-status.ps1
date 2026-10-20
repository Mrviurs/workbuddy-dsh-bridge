
# 运行时目录（本机固定 C:\temp；不存在时自动创建，避免首次运行报错）
if (-not (Test-Path 'C:\temp')) { New-Item -ItemType Directory -Force 'C:\temp' | Out-Null }
# wb-relay-status.ps1 —— 由桌面「WorkBuddy中转状态.cmd」调用
# 一眼看清硬解三件套：自建 serve(8791) / relay(8787) / token 有效期
# 同时给出 DSH 侧配置是否对齐的提示

$ErrorActionPreference = "Continue"
$ServePort = 8791
$RelayPort = 8787
$jwtPath = 'C:\temp\wb-jwt.txt'
$serveTask = 'WorkBuddyCleanServe'
$relayTask = 'WorkBuddyRelay'
$dshHome = if ($env:DSH_HOME) { $env:DSH_HOME } else { Join-Path $env:USERPROFILE '.dsh' }
$patchFile = Join-Path $dshHome 'profiles\desktop\cordis.patch.yml'

function Ok($t)   { Write-Host "  [OK]   $t" -ForegroundColor Green }
function Warn($t) { Write-Host "  [WARN] $t" -ForegroundColor Yellow }
function Bad($t)  { Write-Host "  [FAIL] $t" -ForegroundColor Red }

function Get-JwtExp($jwt) {
  try {
    $p = $jwt.Split('.')[1]
    $b = $p.Replace('-','+').Replace('_','/')
    switch ($b.Length % 4) { 2 { $b += '==' } 3 { $b += '=' } }
    $j = [System.Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($b)) | ConvertFrom-Json
    return $j
  } catch { return $null }
}

Write-Host ""
Write-Host "=== WorkBuddy 中转状态 ===（$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')）" -ForegroundColor Cyan
Write-Host ""

# ---------- 1. 自建 serve ----------
Write-Host "【1】自建 serve（DSH 提示词作为 system 的那一端）" -ForegroundColor White
$listenS = Get-NetTCPConnection -State Listen -LocalPort $ServePort -ErrorAction SilentlyContinue | Select-Object -First 1
if (-not $listenS) {
  Bad "未运行：$ServePort 没有监听 —— 双击「启动WorkBuddy中转.cmd」"
} else {
  $parent = (Get-CimInstance Win32_Process -Filter "ProcessId=$($listenS.OwningProcess)" -ErrorAction SilentlyContinue).ParentProcessId
  $pname = (Get-CimInstance Win32_Process -Filter "ProcessId=$parent" -ErrorAction SilentlyContinue).Name
  Ok "运行中 pid=$($listenS.OwningProcess)  port=$ServePort"
  $taskS = (& schtasks /query /tn $serveTask /fo LIST 2>$null | Select-String 'Status' | Select-Object -First 1)
  if ($taskS) { Write-Host "         计划任务 [$serveTask] $($taskS.Line.Trim())" -ForegroundColor DarkGray }
  try {
    $st = Invoke-RestMethod "http://127.0.0.1:$ServePort/api/v1/auth/status" -Headers @{ 'x-codebuddy-request' = '1' } -TimeoutSec 8
    if ($st.authenticated) { Ok "上游已登录（authEnabled=$($st.authEnabled) authenticated=$($st.authenticated)）" }
    else { Bad "上游未登录 —— token 可能过期，双击启动脚本重扫" }
  } catch { Warn "serve 探活失败：$($_.Exception.Message)" }
}

# ---------- 2. relay ----------
Write-Host ""
Write-Host "【2】relay（DSH 实际连接的 OpenAI 兼容口）" -ForegroundColor White
$listenR = Get-NetTCPConnection -State Listen -LocalPort $RelayPort -ErrorAction SilentlyContinue | Select-Object -First 1
if (-not $listenR) {
  Bad "未运行：$RelayPort 没有监听 —— 双击「启动WorkBuddy中转.cmd」"
} else {
  Ok "运行中 pid=$($listenR.OwningProcess)  http://127.0.0.1:$RelayPort/v1"
  $taskR = (& schtasks /query /tn $relayTask /fo LIST 2>$null | Select-String 'Status' | Select-Object -First 1)
  if ($taskR) { Write-Host "         计划任务 [$relayTask] $($taskR.Line.Trim())" -ForegroundColor DarkGray }
  try {
    $h = Invoke-RestMethod "http://127.0.0.1:$RelayPort/health" -TimeoutSec 8
    Write-Host "         上游      : $($h.base)"
    Write-Host "         当前模型  : $($h.model)"
    Write-Host "         提示词模式: $($h.systemMode)（tail=节选 / full=全文作为 system）"
    if ($h.base -match ":$ServePort") { Ok "硬解模式（指向自建 serve）" }
    else { Warn "旧模式（绑 WorkBuddy 自己的 serve，上游有手）—— 建议切硬解" }
    try {
      $models = (Invoke-RestMethod "http://127.0.0.1:$RelayPort/v1/models" -TimeoutSec 8).data.id
      Write-Host "         可用模型  : $(($models | Select-Object -First 6) -join ', ')…（共 $($models.Count) 个）" -ForegroundColor DarkGray
    } catch {}
  } catch { Warn "relay /health 不通：$($_.Exception.Message)" }
}

# ---------- 3. token ----------
Write-Host ""
Write-Host "【3】账号 token（上游认证凭据）" -ForegroundColor White
if (-not (Test-Path $jwtPath)) {
  Bad "没有缓存文件 $jwtPath —— 双击启动脚本会自动从 WorkBuddy 内存里扫"
} else {
  $jwt = (Get-Content $jwtPath -Raw).Trim()
  $j = Get-JwtExp $jwt
  if (-not $j -or -not $j.exp) { Warn "无法解析（len=$($jwt.Length)），双击启动脚本重扫" }
  else {
    $exp = [DateTimeOffset]::FromUnixTimeSeconds([long]$j.exp).LocalDateTime
    $left = [Math]::Round(($exp - (Get-Date)).TotalDays, 1)
    if ($left -lt 0) { Bad "已过期（$exp）—— 打开 WorkBuddy 发一句话后双击启动脚本重扫" }
    elseif ($left -lt 3) { Warn "即将过期：$exp（剩 $left 天）" }
    else { Ok "有效：$exp（剩 $left 天）" }
    Write-Host "         长度 $($jwt.Length) 字符   sub=$($j.sub)   scope=$($j.scope)" -ForegroundColor DarkGray
  }
}

# ---------- 4. DSH 侧 ----------
Write-Host ""
Write-Host "【4】DSH 侧配置" -ForegroundColor White
if (Test-Path $patchFile) {
  $p = Get-Content $patchFile -Raw -Encoding UTF8
  if ($p -match 'baseURL:\s*(\S+)') { Write-Host "         provider baseURL : $($matches[1])" }
  if ($p -match '- id: agent-default-model[\s\S]{0,200}?provider:\s*(\S+)') {
    $dp = $matches[1]
    if ($dp -eq 'workbuddy') { Write-Host "         默认模型 provider: $dp  ← 你最后一次在 DSH 里选的是脑力通道（切回原生就选不带「脑力·」的模型）" -ForegroundColor Yellow }
    else { Write-Host "         默认模型 provider: $dp（原生路由）" }
  }
  if ($p -match '脑力·') { Ok "模型已标注「脑力·」前缀" } else { Warn "模型名未标注（改过 patch 需重启 DSH）" }
} else { Warn "找不到 $patchFile" }
if ((Get-Content (Join-Path $dshHome '.credentials.yaml') -Raw) -match 'WORKBUDDY_LOCAL_KEY') { Ok "凭据占位 WORKBUDDY_LOCAL_KEY 已配置" }
else { Bad "凭据占位 WORKBUDDY_LOCAL_KEY 缺失（会报 MISSING_CREDENTIAL）" }

Write-Host ""
Write-Host "提示：token 过期 / 报 401 → 打开 WorkBuddy 发一句话 → 双击「启动WorkBuddy中转.cmd」" -ForegroundColor DarkGray
Write-Host "      改过 cordis.patch.yml 的模型名或默认模型 → 需要重启 DSH 桌面端" -ForegroundColor DarkGray
Write-Host ""
