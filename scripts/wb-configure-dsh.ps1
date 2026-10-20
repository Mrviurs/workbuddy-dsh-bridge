# wb-configure-dsh.ps1 —— 把 workbuddy provider 写进 DSH 配置（幂等，可重复运行）
#
# 做的事：
#   1. 找到 <DSH_HOME>\profiles\*\cordis.patch.yml
#   2. 在里面补 workbuddy provider（已存在则跳过）
#   3. 在 <DSH_HOME>\.credentials.yaml 的 refs: 下补 WORKBUDDY_LOCAL_KEY
#   4. 备份原文件，并提示需要重启 DSH
#
# 用法：powershell -ExecutionPolicy Bypass -File .\scripts\wb-configure-dsh.ps1
# 参数：-RelayPort 8787（relay 端口，默认从 settings.psd1 读）

param(
  [int]$RelayPort = 0,
  [switch]$WhatIf
)

$ErrorActionPreference = "Continue"
$root = Split-Path -Parent $PSScriptRoot

function Ok { param($m) Write-Host "  [OK]   $m" -ForegroundColor Green }
function Warn { param($m) Write-Host "  [WARN] $m" -ForegroundColor Yellow }
function Bad { param($m) Write-Host "  [FAIL] $m" -ForegroundColor Red }
function Info { param($m) Write-Host "         $m" -ForegroundColor DarkGray }

Write-Host ""
Write-Host "=== 把 workbuddy provider 写进 DSH 配置 ===" -ForegroundColor Cyan
Write-Host ""

# ---------------------------------------------------------------- 定位 DSH
$dshHome = if ($env:DSH_HOME) { $env:DSH_HOME } else { Join-Path $env:USERPROFILE '.dsh' }
if (-not (Test-Path $dshHome)) {
  Bad "没找到 DSH 配置目录：$dshHome"
  Info "如果这台机器没装 DeepSeek Harness，这一步可以跳过——桥已经能跑，但没有 DSH 可用它"
  exit 1
}
Ok "DSH 配置目录：$dshHome"

if (-not $RelayPort) {
  $cfg = Join-Path $root 'config\settings.psd1'
  $RelayPort = 8787
  if (Test-Path $cfg) {
    try { $S = Import-PowerShellDataFile $cfg; if ($S.RelayPort) { $RelayPort = [int]$S.RelayPort } } catch { }
  }
}

$profilesDir = Join-Path $dshHome 'profiles'
if (-not (Test-Path $profilesDir)) {
  Bad "没找到 $profilesDir —— DSH 可能还没初始化过（先启动一次 DSH 再运行本脚本）"
  exit 1
}

$patches = @(Get-ChildItem $profilesDir -Directory -ErrorAction SilentlyContinue |
             ForEach-Object { Join-Path $_.FullName 'cordis.patch.yml' } |
             Where-Object { Test-Path $_ })

if ($patches.Count -eq 0) {
  Warn "没有任何 profile 的 cordis.patch.yml"
  Info "请先启动一次 DSH（它会在 $profilesDir 下生成 profile），再运行本脚本"
  exit 1
}

# ---------------------------------------------------------------- provider 片段
# 缩进约定（顶层条目 0 缩进）：
#   - id: llm-pi-ai        (0)
#     name: ...            (2)
#     config:              (2)
#       providers:         (4)
#         workbuddy:       (6)
$providerLines = @(
  '      workbuddy:',
  '        displayName: WorkBuddy 脑力通道',
  '        apiKeyEnv: WORKBUDDY_LOCAL_KEY',
  '        api: openai-completions',
  "        baseURL: http://127.0.0.1:$RelayPort/v1",
  '        models:',
  '          - id: wb-deepseek-v4-pro',
  '            name: 脑力·DeepSeek-V4-Pro (WB)',
  '            contextWindow: 1000000',
  '            maxTokens: 128000',
  '            input: [text, image]',
  '          - id: wb-deepseek-flash',
  '            name: 脑力·DeepSeek-V4.1-Flash (WB)',
  '            contextWindow: 1000000',
  '            maxTokens: 65536',
  '            input: [text, image]',
  '          - id: wb-glm-5.3',
  '            name: 脑力·GLM-5.3 (WB)',
  '            contextWindow: 1000000',
  '            maxTokens: 65536',
  '            input: [text, image]',
  '          - id: wb-kimi-k3',
  '            name: 脑力·Kimi-K3 (WB)',
  '            contextWindow: 1000000',
  '            maxTokens: 65536',
  '            input: [text, image]',
  '          - id: wb-minimax-m3',
  '            name: 脑力·MiniMax-M3 (WB)',
  '            contextWindow: 512000',
  '            maxTokens: 65536',
  '            input: [text]'
)

# ---------------------------------------------------------------- 逐个 profile 处理
$changed = 0
foreach ($patch in $patches) {
  $profileName = Split-Path (Split-Path $patch -Parent) -Leaf
  Write-Host ""
  Write-Host "--- profile: $profileName" -ForegroundColor White

  $text = Get-Content $patch -Raw -Encoding UTF8
  if (-not $text) {
    Warn "文件为空，跳过（这不是正常的 profile 配置）"
    continue
  }

  if ($text -match '(?m)^\s+workbuddy:') {
    Ok "已经有 workbuddy provider，跳过"
    continue
  }

  # 只改 agent/host 侧配置：client（web 界面）profile 不需要 provider，
  # 硬加进去只会污染配置。判据：文件里必须提到 llm-pi-ai 或 agent-* 插件。
  if ($text -notmatch 'dsh-llm-pi-ai|agent-default-model|dsh-agent') {
    Warn "这个 profile 看起来是界面/客户端配置（没提到 agent 或 llm-pi-ai），跳过"
    Info "如果你确认它也需要，请手动把 config\cordis.patch.example.yml 粘进去"
    continue
  }

  $lines = @(Get-Content $patch -Encoding UTF8)
  $startIdx = -1
  for ($i = 0; $i -lt $lines.Count; $i++) {
    if ($lines[$i] -match '^\s*-\s+id:\s*llm-pi-ai\s*$') { $startIdx = $i; break }
  }

  $newLines = $null
  if ($startIdx -ge 0) {
    # 找到该条目边界
    $endIdx = $lines.Count
    for ($j = $startIdx + 1; $j -lt $lines.Count; $j++) {
      if ($lines[$j] -match '^\s*-\s+id:\s*\S') { $endIdx = $j; break }
    }
    # 在条目内找 providers: / config:
    $provIdx = -1; $cfgIdx = -1
    for ($j = $startIdx; $j -lt $endIdx; $j++) {
      if ($lines[$j] -match '^\s+providers:\s*$') { $provIdx = $j; break }
      if ($lines[$j] -match '^\s+config:\s*$') { $cfgIdx = $j }
    }

    if ($provIdx -ge 0) {
      $newLines = @()
      $newLines += $lines[0..$provIdx]
      $newLines += $providerLines
      if ($provIdx + 1 -le $lines.Count - 1) { $newLines += $lines[($provIdx + 1)..($lines.Count - 1)] }
      Ok "已在该 profile 的现有 providers: 下插入 workbuddy"
    } elseif ($cfgIdx -ge 0) {
      $newLines = @()
      $newLines += $lines[0..$cfgIdx]
      $newLines += @('    providers:')
      $newLines += $providerLines
      if ($cfgIdx + 1 -le $lines.Count - 1) { $newLines += $lines[($cfgIdx + 1)..($lines.Count - 1)] }
      Ok "已在该 profile 的 llm-pi-ai.config 下新建 providers: 并插入 workbuddy"
    } else {
      Warn "找到 llm-pi-ai 条目但没有 config: 段，改为追加独立条目"
    }
  }

  if (-not $newLines) {
    $newLines = @()
    $newLines += $lines
    if ($newLines.Count -gt 0 -and $newLines[-1].Trim() -ne '') { $newLines += '' }
    $newLines += @(
      '- id: llm-pi-ai',
      '  name: "@deepseek-ai/dsh-llm-pi-ai"',
      '  config:',
      '    providers:'
    )
    $newLines += $providerLines
    Ok "已在文件末尾追加 llm-pi-ai 条目（含 workbuddy provider）"
  }

  if ($WhatIf) {
    Warn "-WhatIf：不写入，共 $($newLines.Count) 行（原 $($lines.Count) 行）"
  } else {
    $bak = "$patch.bak-$(Get-Date -Format 'yyyyMMdd-HHmmss')"
    Copy-Item $patch $bak -Force
    Info "已备份：$(Split-Path $bak -Leaf)"
    [System.IO.File]::WriteAllLines($patch, $newLines, (New-Object System.Text.UTF8Encoding($false)))
    Ok "已写入 $patch"
    $changed++
  }
}

# ---------------------------------------------------------------- 凭据占位
Write-Host ""
Write-Host "--- 凭据占位" -ForegroundColor White
$credFile = Join-Path $dshHome '.credentials.yaml'
if (-not (Test-Path $credFile)) {
  Warn "没有 .credentials.yaml —— DSH 首次启动后才会生成，先启动一次 DSH 再运行本脚本"
} else {
  $cred = Get-Content $credFile -Raw -Encoding UTF8
  if ($cred -match 'WORKBUDDY_LOCAL_KEY') {
    Ok "WORKBUDDY_LOCAL_KEY 已存在，跳过"
  } else {
    $cl = @(Get-Content $credFile -Encoding UTF8)
    $refsIdx = -1
    for ($i = 0; $i -lt $cl.Count; $i++) {
      if ($cl[$i] -match '^refs:\s*$') { $refsIdx = $i; break }
    }
    $newCl = $null
    if ($refsIdx -ge 0) {
      # 插到 refs: 下面第一行（保持其它 ref 的顺序无所谓）
      $newCl = @()
      $newCl += $cl[0..$refsIdx]
      $newCl += '  WORKBUDDY_LOCAL_KEY: local-relay-placeholder'
      if ($refsIdx + 1 -le $cl.Count - 1) { $newCl += $cl[($refsIdx + 1)..($cl.Count - 1)] }
      Ok "已在现有 refs: 下补 WORKBUDDY_LOCAL_KEY"
    } else {
      $newCl = @($cl) + @('refs:', '  WORKBUDDY_LOCAL_KEY: local-relay-placeholder')
      Ok "已追加 refs: 段并写入 WORKBUDDY_LOCAL_KEY"
    }
    if (-not $WhatIf) {
      $bak = "$credFile.bak-$(Get-Date -Format 'yyyyMMdd-HHmmss')"
      Copy-Item $credFile $bak -Force
      Info "已备份：$(Split-Path $bak -Leaf)"
      [System.IO.File]::WriteAllLines($credFile, $newCl, (New-Object System.Text.UTF8Encoding($false)))
      Ok "已写入 $credFile"
      $changed++
    } else {
      Warn "-WhatIf：不写入"
    }
  }
}

# ---------------------------------------------------------------- 结果
Write-Host ""
if ($changed -gt 0 -and -not $WhatIf) {
  Write-Host "=== 配置完成 ===" -ForegroundColor Cyan
  Write-Host "  ★ 现在必须【完全退出 DSH 再重新打开】，模型下拉里才会出现「脑力·」系列" -ForegroundColor Yellow
  Write-Host ""
  Write-Host "  如果重启后还是没有：" -ForegroundColor Gray
  Write-Host "    1. 确认 $(Join-Path $dshHome 'profiles') 下有多个 profile 时，你用的那个已被改到" -ForegroundColor DarkGray
  Write-Host "    2. 打开界面点「复制诊断报告」，把内容发给作者" -ForegroundColor DarkGray
} elseif ($changed -eq 0 -and -not $WhatIf) {
  Write-Host "=== 无需修改（已经配置过）===" -ForegroundColor Cyan
  Write-Host "  如果 DSH 里仍然看不到「脑力·」模型，请【完全退出 DSH 再重新打开】" -ForegroundColor Yellow
  Write-Host "  （配置改动只有重启才生效；只关窗口不算退出）" -ForegroundColor DarkGray
}
Write-Host ""
