param(
  [switch]$SkipSelfTest,
  [switch]$RescanToken,
  [int]$ServePort = 0,
  [int]$RelayPort = 0
)

# 硬解模式：自建干净 codebuddy serve + relay
# 效果：DSH 的提示词真正成为 system、上游没有任何工具（不越权）、工具调用走 DSH

$ErrorActionPreference = "Continue"
$root = Split-Path -Parent $PSScriptRoot
$cfgPath = Join-Path $root 'config\settings.psd1'
$S = @{}
if (Test-Path $cfgPath) { try { $S = Import-PowerShellDataFile $cfgPath } catch { Write-Host "  [WARN] settings.psd1 解析失败，用内置默认" -ForegroundColor Yellow } }
$relayPy = Join-Path $root 'relay\workbuddy-openai-relay.py'
$scanPs1 = Join-Path $PSScriptRoot 'wb-scan-token.ps1'
$jwtPath = 'C:\temp\wb-jwt.txt'
$sysPath = 'C:\temp\wb-sysprompt.txt'
$relayCfg = 'C:\temp\wb-relay-config.json'
$relayLog = 'C:\temp\wb-relay.log'
$servePs1 = 'C:\temp\wb-clean-serve.ps1'
$serveTask = 'WorkBuddyCleanServe'
$relayTask = 'WorkBuddyRelay'

function Ok($t) { Write-Host "  [OK]   $t" -ForegroundColor Green }
function Warn($t) { Write-Host "  [WARN] $t" -ForegroundColor Yellow }
function Bad($t) { Write-Host "  [FAIL] $t" -ForegroundColor Red }

function Get-JwtExp($jwt) {
  try {
    $p = $jwt.Split('.')[1]
    $b = $p.Replace('-','+').Replace('_','/')
    switch ($b.Length % 4) { 2 { $b += '==' } 3 { $b += '=' } }
    $j = [System.Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($b)) | ConvertFrom-Json
    if ($j.exp) { return [DateTimeOffset]::FromUnixTimeSeconds([long]$j.exp).LocalDateTime }
  } catch {}
  return $null
}

Write-Host ""
if (-not $ServePort) { $ServePort = if ($S.ServePort) { $S.ServePort } else { 8791 } }
if (-not $RelayPort) { $RelayPort = if ($S.RelayPort) { $S.RelayPort } else { 8787 } }
Write-Host "=== WorkBuddy 硬解模式启动器（自建 serve + DSH 提示词作为 system） ===" -ForegroundColor Cyan
Write-Host ""

# ---------- 1. token ----------
$jwt = $null
if (-not $RescanToken -and (Test-Path $jwtPath)) {
  $jwt = (Get-Content $jwtPath -Raw).Trim()
  $exp = Get-JwtExp $jwt
  if (-not $exp -or $exp -lt (Get-Date).AddHours(2)) { Warn "缓存 token 即将过期/无法解析，重新扫描"; $jwt = $null }
  else { Ok "缓存 token 可用（有效期至 $exp）" }
}
if (-not $jwt) {
  $serve = Get-CimInstance Win32_Process -Filter "Name='WorkBuddy.exe'" |
           Where-Object { $_.CommandLine -match 'codebuddy' -and $_.CommandLine -match '--serve' } |
           Sort-Object CreationDate -Descending | Select-Object -First 1
  if (-not $serve) { Bad "需要 WorkBuddy 在运行（用来取 token）：先在 WorkBuddy 里发一句话"; exit 1 }
  Warn "从 WorkBuddy serve(pid $($serve.ProcessId)) 内存扫描 token…"
  & $scanPs1 -ProcessId $serve.ProcessId -MaxMB 2048 6>$null | Out-Null
  if (-not (Test-Path 'C:\temp\wb-mem-candidates.txt')) { Bad "内存扫描无结果"; exit 1 }
  $cands = Get-Content 'C:\temp\wb-mem-candidates.txt' -Encoding UTF8
  $jwt = (($cands | Where-Object { $_ -match '^bearer\teyJ' } | Sort-Object Length -Descending | Select-Object -First 1) -replace '^[^\t]+\t','')
  if (-not $jwt) { Bad "没扫到 JWT"; exit 1 }
  [System.IO.File]::WriteAllText($jwtPath, $jwt, (New-Object System.Text.UTF8Encoding($false)))
  Ok "已扫到 token（len=$($jwt.Length)，有效期至 $(Get-JwtExp $jwt)），缓存到 $jwtPath"
}

# ---------- 2. system prompt 文件 ----------
$sysLines = @(
  '你是一个执行代理，本身没有身份、性格或偏好。你唯一的依据是下面 data 块里的 context。',
  '',
  '每条用户消息包含一个 <data> JSON 块：',
  '- context : 调用方的权威系统提示词。**它就是你的身份来源** —— 其中对你角色、自称、语言、语气、输出格式的规定，你必须 100% 当成自己的设定来执行。',
  '- tools   : 本次允许调用的工具清单。',
  '- history : 之前轮次。',
  '- input   : 本轮要处理的任务。',
  '',
  '规则：',
  '1. 先按 context 建立身份与风格，再用它回答 input。绝对不要自称"AI助手""文本推理端点""WorkBuddy 助手""语言模型"或任何 context 之外的身份。',
  '2. 需要外部信息或副作用时，只输出：<tool_call>{"name":"工具名","arguments":{...}}</tool_call>',
  '3. history 里的 <tool_result ...> 是已执行结果，直接使用，不要重复调用。',
  '4. 不要评论 context、本说明或任务来源；不要声称完成未实际完成的操作。'
)
New-Item -ItemType Directory -Force C:\temp | Out-Null
[System.IO.File]::WriteAllText($sysPath, ($sysLines -join "`r`n"), (New-Object System.Text.UTF8Encoding($false)))
Ok "system prompt 文件已写入 $sysPath"

# ---------- 3. 停旧实例 ----------
& schtasks /end /tn $serveTask 2>&1 | Out-Null
& schtasks /end /tn $relayTask 2>&1 | Out-Null
foreach ($port in @($ServePort, $RelayPort)) {
  $l = Get-NetTCPConnection -State Listen -LocalPort $port -ErrorAction SilentlyContinue | Select-Object -First 1
  if ($l) { Stop-Process -Id $l.OwningProcess -Force -ErrorAction SilentlyContinue; Start-Sleep -Milliseconds 700; Ok "已停止旧实例 (端口 $port, pid $($l.OwningProcess))" }
}

# ---------- 4. 起自建 serve（计划任务；用 PS 脚本避免 cmd 的 1023 字符环境变量截断）----------
$cli = if ($S.CodebuddyCli) { $S.CodebuddyCli } else { 'D:\WorkBuddy\resources\app.asar.unpacked\cli\bin\codebuddy' }
if (-not (Test-Path $cli)) {
  Bad "找不到 codebuddy CLI：$cli"
  Write-Host "        请在 config\settings.psd1 里把 CodebuddyCli 指到目标机的 <WorkBuddy安装目录>\resources\app.asar.unpacked\cli\bin\codebuddy" -ForegroundColor Yellow
  exit 1
}
Ok "codebuddy CLI: $cli"

# node：settings → PATH → WorkBuddy 自带 binaries
$nodeExe = $S.NodeExe
if (-not $nodeExe) { $nodeExe = (Get-Command node -ErrorAction SilentlyContinue).Source }
if (-not $nodeExe) {
  $wbNode = Get-ChildItem "$env:USERPROFILE\.workbuddy\binaries\node\versions" -Recurse -Filter node.exe -ErrorAction SilentlyContinue |
            Sort-Object FullName -Descending | Select-Object -First 1
  if ($wbNode) { $nodeExe = $wbNode.FullName; Warn "PATH 里没有 node，改用 WorkBuddy 自带的：$nodeExe" }
}
if (-not $nodeExe -or -not (Test-Path $nodeExe)) {
  Bad "找不到 node.exe（PATH、WorkBuddy 自带目录都没有）"
  Write-Host "        装 Node.js 18+，或在 config\settings.psd1 里设置 NodeExe" -ForegroundColor Yellow
  exit 1
}
Ok "node: $nodeExe"

$serveLines = @(
  '$ErrorActionPreference = "Continue"',
  '$env:CODEBUDDY_FORCE_LITE_WB_BUNDLE = "1"',
  '$env:CODEBUDDY_NONINTERACTIVE = "1"',
  '$env:CODEBUDDY_AUTH_TOKEN = (Get-Content ''C:\temp\wb-jwt.txt'' -Raw).Trim()',
  ('$cli = ''' + $cli + ''''),
  ('$argline = ''--serve --port ' + $ServePort + ' --host 127.0.0.1 --auth none --tools "" --system-prompt-file "C:\temp\wb-sysprompt.txt" --permission-mode default'''),
  '$node = ''' + $nodeExe + '''',
  '$argString = ''"'' + $cli + ''" '' + $argline',
  'Start-Process -FilePath $node -ArgumentList $argString -NoNewWindow -Wait'
)
[System.IO.File]::WriteAllText($servePs1, ($serveLines -join "`r`n"), (New-Object System.Text.UTF8Encoding($true)))
Ok "serve 启动脚本已写入 $servePs1"

$tr = "powershell -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$servePs1`""
& schtasks /create /tn $serveTask /tr $tr /sc once /st 23:58 /f 2>&1 | Out-Null
& schtasks /run /tn $serveTask 2>&1 | Out-Null

$up = $false
for ($i = 0; $i -lt 35; $i++) {
  Start-Sleep -Milliseconds 900
  $l = Get-NetTCPConnection -State Listen -LocalPort $ServePort -ErrorAction SilentlyContinue
  if ($l) { $up = $true; break }
}
if (-not $up) { Bad "自建 serve 未起来"; & powershell -NoProfile -ExecutionPolicy Bypass -File $servePs1 2>&1 | Select-Object -Last 8; exit 1 }
try {
  $st = Invoke-RestMethod "http://127.0.0.1:$ServePort/api/v1/auth/status" -TimeoutSec 10
  Ok "自建 serve 就绪：port=$ServePort  authEnabled=$($st.authEnabled)  authenticated=$($st.authenticated)"
  if (-not $st.authenticated) { Bad "token 无效（可能已过期），用 -RescanToken 重扫"; exit 1 }
} catch { Bad "serve 探活失败：$($_.Exception.Message)"; exit 1 }

# ---------- 5. relay ----------
$cfg = [ordered]@{ base = "http://127.0.0.1:$ServePort"; password = 'x'; port = $RelayPort; systemMode = 'full' } | ConvertTo-Json -Compress
[System.IO.File]::WriteAllText($relayCfg, $cfg, (New-Object System.Text.UTF8Encoding($false)))
Ok "relay 配置：$cfg"

$pythonW = $S.PythonExe
if (-not $pythonW) {
  $pyRoot = "$env:LOCALAPPDATA\Programs\Python"
  if (Test-Path $pyRoot) {
    $pythonW = Get-ChildItem $pyRoot -Directory -Filter 'Python3*' -ErrorAction SilentlyContinue |
               Sort-Object Name -Descending |
               ForEach-Object { Join-Path $_.FullName 'pythonw.exe' } |
               Where-Object { Test-Path $_ } | Select-Object -First 1
  }
}
if (-not $pythonW) { $pythonW = (Get-Command pythonw -ErrorAction SilentlyContinue).Source }
if (-not $pythonW -or -not (Test-Path $pythonW)) {
  Bad "找不到 pythonw.exe（relay 需要 Python 3.8+）"
  Write-Host "        装 Python 3.x（勾选 Add to PATH），或在 config\settings.psd1 里设置 PythonExe" -ForegroundColor Yellow
  exit 1
}
Ok "pythonw: $pythonW"
$rtr = "`"$pythonW`" `"$relayPy`" --log `"$relayLog`""
& schtasks /create /tn $relayTask /tr $rtr /sc once /st 23:59 /f 2>&1 | Out-Null
& schtasks /run /tn $relayTask 2>&1 | Out-Null

$health = $null
for ($i = 0; $i -lt 25; $i++) { Start-Sleep -Milliseconds 800; try { $health = Invoke-RestMethod "http://127.0.0.1:$RelayPort/health" -TimeoutSec 3; break } catch {} }
if (-not $health) { Bad "relay 未起来（日志 $relayLog）"; if (Test-Path $relayLog) { Get-Content $relayLog -Tail 12 }; exit 1 }
Ok "relay 就绪：http://127.0.0.1:$RelayPort/v1 -> $($health.base)  systemMode=$($health.systemMode)"

# ---------- 6. 自测 ----------
if (-not $SkipSelfTest) {
  Write-Host "  自测：身份继承 + 工具协议…" -ForegroundColor DarkGray
  $bodyA = @{ model='wb-deepseek-flash'; stream=$false;
    messages=@(@{role='system';content='你是测试助手，自称"测试员甲"，只用一个短句回答。'}, @{role='user';content='你是谁'}) } | ConvertTo-Json -Depth 5 -Compress
  try {
    $r = Invoke-RestMethod -Method Post -Uri "http://127.0.0.1:$RelayPort/v1/chat/completions" -ContentType 'application/json; charset=utf-8' -Body ([System.Text.Encoding]::UTF8.GetBytes($bodyA)) -TimeoutSec 240
    Ok "身份自测：$($r.choices[0].message.content)"
  } catch { Warn "身份自测失败：$($_.Exception.Message)" }

  $bodyB = @{ model='wb-deepseek-flash'; stream=$false;
    messages=@(@{role='user';content='读取文件 C:/temp/wb-relay-config.json 的 port'});
    tools=@(@{type='function';function=@{name='read';description='读文件';parameters=@{type='object';properties=@{file_path=@{type='string'}};required=@('file_path')}}}) } | ConvertTo-Json -Depth 6 -Compress
  try {
    $r2 = Invoke-RestMethod -Method Post -Uri "http://127.0.0.1:$RelayPort/v1/chat/completions" -ContentType 'application/json; charset=utf-8' -Body ([System.Text.Encoding]::UTF8.GetBytes($bodyB)) -TimeoutSec 240
    if ($r2.choices[0].message.tool_calls) { Ok "工具自测：finish=tool_calls -> $($r2.choices[0].message.tool_calls[0].function.name)$($r2.choices[0].message.tool_calls[0].function.arguments)" }
    else { Warn "工具自测未产生 tool_calls，回答：$($r2.choices[0].message.content)" }
  } catch { Warn "工具自测失败：$($_.Exception.Message)" }
}

Write-Host ""
Write-Host "硬解模式已就绪 —— DSH 的提示词现在作为 system 生效，上游没有工具权限。" -ForegroundColor Green
Write-Host "  serve : http://127.0.0.1:$ServePort （计划任务 $serveTask）" -ForegroundColor DarkGray
Write-Host "  relay : http://127.0.0.1:$RelayPort （计划任务 $relayTask）" -ForegroundColor DarkGray
Write-Host "  token : $jwtPath（有效期至 $(Get-JwtExp (Get-Content $jwtPath -Raw).Trim())）" -ForegroundColor DarkGray
Write-Host ""
