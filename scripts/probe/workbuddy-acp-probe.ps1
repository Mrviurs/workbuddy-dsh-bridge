# workbuddy-acp-probe.ps1  (v2)
# 一次跑完 WorkBuddy 反代链路的全部验证：
#   1) 鉴权自证（会话列表）
#   2) 会话详情
#   3) ACP bootstrap -> 拿 Acp-Connection-Id
#   4) session/set_model 切模型
#   5) session/prompt 发一条，dump SSE 事件原文（这是转换层要的形状）
#
# token 来源（三选一，都不写进任何持久文件）：
#   A. .\workbuddy-acp-probe.ps1 -TokenFile C:\temp\wb-token.txt
#   B. $env:WB_TOKEN="xxx"   然后 .\workbuddy-acp-probe.ps1
#   C. .\workbuddy-acp-probe.ps1 -Token "xxx"
#
# 用法：
#   .\workbuddy-acp-probe.ps1 -TokenFile C:\temp\wb-token.txt

param(
  [string]$Token = "",
  [string]$TokenFile = "",
  [string]$UserId = "<YOUR_USER_ID>",
  [string]$Base = "https://www.workbuddy.cn",
  [string]$ConversationId = "",
  [string]$ModelId = "deepseek-v4-pro",
  [switch]$SkipPrompt
)

$ErrorActionPreference = "Continue"
Add-Type -AssemblyName System.Net.Http -ErrorAction SilentlyContinue

# ---------- token 解析 ----------
if (-not $Token -and $TokenFile) {
  if (Test-Path $TokenFile) { $Token = (Get-Content $TokenFile -Raw).Trim() } else { Write-Host "token 文件不存在: $TokenFile" -ForegroundColor Red; exit 1 }
}
if (-not $Token) { $Token = $env:WB_TOKEN }
if (-not $Token) { Write-Host "缺 token：用 -TokenFile / -Token / `$env:WB_TOKEN" -ForegroundColor Red; exit 1 }
$Token = $Token -replace '^\s*Bearer\s+', ''
if ($Token.Length -lt 20) { Write-Host "token 太短，确认复制完整（不含 Bearer 前缀也行）" -ForegroundColor Red; exit 1 }
Write-Host "token: 长度 $($Token.Length)，尾部 …$($Token.Substring([Math]::Max(0,$Token.Length-6)))" -ForegroundColor DarkGray

$H = @{
  "Authorization"       = "Bearer $Token"
  "X-User-Id"           = $UserId
  "X-Domain"            = "www.workbuddy.cn"
  "x-codebuddy-request" = "1"
  "Accept"              = "application/json, text/event-stream"
  "Content-Type"        = "application/json"
  "User-Agent"          = "WorkBuddy/5.8.3"
}

function Show-Resp($title, $resp) {
  Write-Host "`n===== $title =====" -ForegroundColor Cyan
  Write-Host "STATUS $($resp.StatusCode)"
  foreach ($k in "Acp-Connection-Id","Acp-Session-Token","Content-Type") {
    $v = $resp.Headers[$k]; if ($v) { Write-Host "HDR $k = $v" }
  }
  $b = [string]$resp.Content
  if ($b.Length -gt 500) { $b = $b.Substring(0,500) + " …" }
  Write-Host $b
}

function Fail($title, $err) {
  Write-Host "`n===== $title =====" -ForegroundColor Red
  Write-Host "ERR $($err.Exception.Message)"
}

# ---------- 1) 鉴权自证 ----------
$listUrl = "$Base/console/as/conversations/?type=cloud&size=5"
$convs = @()
try {
  $r = Invoke-WebRequest -Uri $listUrl -Headers $H -Method GET -TimeoutSec 20 -UseBasicParsing
  Show-Resp "1) 会话列表（200 = token 有效）" $r
  $j = $r.Content | ConvertFrom-Json
  $items = $null
  if ($j.data -is [array]) { $items = $j.data } elseif ($j.data.list) { $items = $j.data.list } elseif ($j.conversations) { $items = $j.conversations }
  if ($items) { $convs = @($items | ForEach-Object { $_.id } | Where-Object { $_ }) }
  if ($convs.Count) { Write-Host "可用会话 id: $($convs -join ', ')" -ForegroundColor DarkGray }
} catch { Fail "1) 会话列表" $_ }

# ---------- 2) 会话详情 ----------
if (-not $ConversationId) {
  if ($convs.Count) { $ConversationId = $convs[0] }
  else {
    $cache = Join-Path $env:USERPROFILE ".workbuddy\storage\user-$UserId-personal\scoped\c7389fe09fa872c0\conversation-list.json"
    if (Test-Path $cache) {
      try {
        $cj = Get-Content $cache -Raw -Encoding UTF8 | ConvertFrom-Json
        $cid = ($cj.PSObject.Properties | Where-Object { $_.Name -like 'project:v1:*' } | Select-Object -First 1).Value.items | Select-Object -First 1
        if ($cid) { $ConversationId = $cid.id }
      } catch {}
    }
  }
}
if (-not $ConversationId) { Write-Host "`n拿不到会话 id，后续跳过" -ForegroundColor Red; exit 1 }
Write-Host "`n使用会话 id: $ConversationId" -ForegroundColor Yellow

try {
  $r2 = Invoke-WebRequest -Uri "$Base/console/as/conversations/$ConversationId" -Headers $H -Method GET -TimeoutSec 20 -UseBasicParsing
  $b = [string]$r2.Content; if ($b.Length -gt 400) { $b = $b.Substring(0,400) + " …" }
  Write-Host "`n===== 2) 会话详情 =====" -ForegroundColor Cyan; Write-Host "STATUS $($r2.StatusCode)"; Write-Host $b
} catch { Fail "2) 会话详情" $_ }

# ---------- 3) bootstrap ----------
$acpConn = $null
$bootBody = '{"jsonrpc":"2.0","id":1,"method":"session/new","params":{"cwd":"D:/","mcpServers":[]}}'
try {
  $r3 = Invoke-WebRequest -Uri "$Base/console/as/conversations/$ConversationId/acp/bootstrap" -Headers $H -Method POST -Body $bootBody -TimeoutSec 30 -UseBasicParsing
  $acpConn = $r3.Headers["Acp-Connection-Id"]
  if (-not $acpConn) { $acpConn = $r3.Headers["acp-connection-id"] }
  Show-Resp "3) ACP bootstrap" $r3
  if ($acpConn) { Write-Host ">>> Acp-Connection-Id = $acpConn" -ForegroundColor Green } else { Write-Host ">>> 没拿到 Acp-Connection-Id" -ForegroundColor Yellow }
} catch { Fail "3) ACP bootstrap" $_ }

# ---------- 4)+5) set_model + prompt，并 dump SSE ----------
function Invoke-AcpStream($title, $path, $body, $extraHeaders, $seconds = 25) {
  Write-Host "`n===== $title =====" -ForegroundColor Cyan
  try {
    $client = [System.Net.Http.HttpClient]::new()
    $client.Timeout = [TimeSpan]::FromSeconds($seconds)
    $req = [System.Net.Http.HttpRequestMessage]::new([System.Net.Http.HttpMethod]::Post, "$Base$path")
    foreach ($k in $H.Keys) { [void]$req.Headers.TryAddWithoutValidation($k, $H[$k]) }
    foreach ($k in $extraHeaders.Keys) { [void]$req.Headers.TryAddWithoutValidation($k, $extraHeaders[$k]) }
    $req.Content = [System.Net.Http.StringContent]::new($body, [System.Text.Encoding]::UTF8, "application/json")
    $resp = $client.SendAsync($req, [System.Net.Http.HttpCompletionOption]::ResponseHeadersRead).Result
    Write-Host "STATUS $([int]$resp.StatusCode)"
    foreach ($hk in "Acp-Connection-Id","Content-Type") {
      $vals = $null
      if ($resp.Headers.TryGetValues($hk, [ref]$vals)) { Write-Host "HDR $hk = $($vals -join ',')" }
    }
    $stream = $resp.Content.ReadAsStreamAsync().Result
    $reader = [System.IO.StreamReader]::new($stream)
    $buf = New-Object char[] 4000
    $n = $reader.Read($buf, 0, 4000)
    if ($n -gt 0) { Write-Host (-join $buf[0..($n-1)]) } else { Write-Host "(无数据)" }
    try { $client.CancelPendingRequests() } catch {}
  } catch {
    Write-Host "ERR $($_.Exception.GetBaseException().Message)" -ForegroundColor Red
  }
}

if ($acpConn -and -not $SkipPrompt) {
  $extra = @{ "acp-connection-id" = [string]$acpConn }
  $path = "/console/as/conversations/$ConversationId/acp"

  $setModel = '{"jsonrpc":"2.0","id":9,"method":"session/set_model","params":{"sessionId":"' + $ConversationId + '","modelId":"' + $ModelId + '"}}'
  Invoke-AcpStream "4) session/set_model -> $ModelId" $path $setModel $extra 15

  $promptTxt = "只回复两个字：通了吗"
  $promptBody = '{"jsonrpc":"2.0","id":2,"method":"session/prompt","params":{"sessionId":"' + $ConversationId + '","prompt":[{"type":"text","text":"' + $promptTxt + '"}]}}'
  Invoke-AcpStream "5) session/prompt -> SSE 事件原文" $path $promptBody $extra 30
}

Write-Host @"

===== 判断标准 =====
  1) 200            -> token 有效
  3) 有 Acp-Connection-Id -> 反代链路成立
  5) 能看到 session/update / agent_message_chunk / content.text
                    -> 转换层可以定稿，把它整段贴给我即可
"@ -ForegroundColor Yellow
