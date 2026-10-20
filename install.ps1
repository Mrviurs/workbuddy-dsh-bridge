# install.ps1 —— 一键安装：检查环境 → 生成配置 → 建桌面快捷方式 → 首次启动
#
# 用法（在项目根目录）：
#   powershell -ExecutionPolicy Bypass -File .\install.ps1
# 或直接双击项目里的「一键安装.cmd」
#
# 可选参数：
#   -SkipShortcuts   不创建桌面快捷方式
#   -SkipStart       只做准备，不启动服务
#   -Force           重跑并覆盖已有配置（会备份原 settings.psd1）

param(
  [switch]$SkipShortcuts,
  [switch]$SkipStart,
  [switch]$Force
)

$ErrorActionPreference = "Continue"
$root = $PSScriptRoot
$ok = { param($m) Write-Host "  [OK]   $m" -ForegroundColor Green }
$warn = { param($m) Write-Host "  [WARN] $m" -ForegroundColor Yellow }
$bad = { param($m) Write-Host "  [FAIL] $m" -ForegroundColor Red }
$step = { param($m) Write-Host "`n$m" -ForegroundColor Cyan }

Write-Host ""
Write-Host "=== WorkBuddy 中转工具 · 一键安装 ===" -ForegroundColor Cyan
Write-Host "    项目目录：$root" -ForegroundColor DarkGray

# ---------------------------------------------------------------- 1. 环境检查
& $step "[1/5] 检查运行环境"

function Find-Node {
  $c = (Get-Command node -ErrorAction SilentlyContinue).Source
  if ($c) { return $c }
  $wb = Get-ChildItem "$env:USERPROFILE\.workbuddy\binaries\node\versions" -Recurse -Filter node.exe -ErrorAction SilentlyContinue |
        Sort-Object FullName -Descending | Select-Object -First 1
  if ($wb) { return $wb.FullName }
  return $null
}

function Find-PythonW {
  $pyRoot = "$env:LOCALAPPDATA\Programs\Python"
  if (Test-Path $pyRoot) {
    $c = Get-ChildItem $pyRoot -Directory -Filter 'Python3*' -ErrorAction SilentlyContinue |
         Sort-Object Name -Descending |
         ForEach-Object { Join-Path $_.FullName 'pythonw.exe' } |
         Where-Object { Test-Path $_ } | Select-Object -First 1
    if ($c) { return $c }
  }
  $p = (Get-Command pythonw -ErrorAction SilentlyContinue).Source
  if ($p) { return $p }
  return $null
}

function Find-CodebuddyCli {
  $rel = 'resources\app.asar.unpacked\cli\bin\codebuddy'
  $cands = @(
    (Join-Path $env:LOCALAPPDATA "Programs\WorkBuddy\$rel"),
    (Join-Path $env:LOCALAPPDATA "WorkBuddy\$rel"),
    (Join-Path $env:ProgramFiles "WorkBuddy\$rel"),
    (Join-Path ${env:ProgramFiles(x86)} "WorkBuddy\$rel"),
    (Join-Path $env:USERPROFILE ".workbuddy\$rel"),
    "D:\WorkBuddy\$rel",
    "E:\WorkBuddy\$rel"
  )
  foreach ($c in $cands) { if (Test-Path $c) { return $c } }
  # 常见位置都没找到，扫各盘根目录下名字带 WorkBuddy 的文件夹（只扫一层，不会很慢）
  foreach ($drive in @('C:\', 'D:\', 'E:\', 'F:\')) {
    if (-not (Test-Path $drive)) { continue }
    $hit = Get-ChildItem $drive -Directory -Filter 'WorkBuddy*' -ErrorAction SilentlyContinue |
           ForEach-Object { Join-Path $_.FullName $rel } |
           Where-Object { Test-Path $_ } | Select-Object -First 1
    if ($hit) { return $hit }
  }
  return $null
}

$nodeExe = Find-Node
if ($nodeExe) { & $ok "node: $nodeExe" }
else { & $bad "找不到 node.exe —— 请装 Node.js 18+，或在 config\settings.psd1 里设置 NodeExe"; exit 1 }

$pythonW = Find-PythonW
if ($pythonW) { & $ok "python: $pythonW" }
else { & $bad "找不到 pythonw.exe —— 请装 Python 3.8+（安装时勾选 Add to PATH）"; exit 1 }

$cli = Find-CodebuddyCli
if ($cli) { & $ok "WorkBuddy CLI: $cli" }
else {
  & $bad "找不到 WorkBuddy 的 codebuddy CLI"
  Write-Host "        请确认 WorkBuddy 已安装；或手动在 config\settings.psd1 填 CodebuddyCli" -ForegroundColor Yellow
  Write-Host "        搜索命令：Get-ChildItem C:\,D:\ -Recurse -Filter codebuddy -ErrorAction SilentlyContinue | Where-Object { `$_.FullName -like '*app.asar.unpacked\cli\bin\codebuddy' }" -ForegroundColor DarkGray
  exit 1
}

# WorkBuddy 是否在运行（token 要从它的进程内存里取）
# 不同版本的 WorkBuddy 承载 CLI 的进程名不一样（WorkBuddy.exe / node.exe / CodeBuddy.exe）
$wbProcCands = @()
try {
  $wbProcCands = Get-CimInstance Win32_Process -ErrorAction Stop | Where-Object {
    ($_.Name -match '^(WorkBuddy|CodeBuddy|codebuddy)') -or
    ($_.Name -match '^node' -and $_.CommandLine -and $_.CommandLine -match 'codebuddy|workbuddy')
  }
} catch { }
if ($wbProcCands.Count -gt 0) {
  $serving = @($wbProcCands | Where-Object { $_.CommandLine -and $_.CommandLine -match '--serve' })
  & $ok ("WorkBuddy 正在运行（{0} 个相关进程{1}）" -f $wbProcCands.Count, $(if ($serving.Count) { "，其中 $($serving.Count) 个 serve" } else { "" }))
} else {
  & $warn "没检测到 WorkBuddy 进程 —— 请打开 WorkBuddy、登录、随便发一句话，再重跑本脚本"
  & $warn "（若确认 WorkBuddy 已打开，跑 scripts\wb-doctor.ps1 把输出发给作者）"
}

# ---------------------------------------------------------------- 2. 生成配置
& $step "[2/5] 写入配置"

$cfgPath = Join-Path $root 'config\settings.psd1'
$example = Join-Path $root 'config\settings.example.psd1'

if ($Force -and (Test-Path $cfgPath)) {
  $bak = "$cfgPath.bak-$(Get-Date -Format 'yyyyMMdd-HHmmss')"
  Copy-Item $cfgPath $bak -Force
  & $warn "已备份旧配置：$bak"
}

if (-not (Test-Path $cfgPath)) {
  Copy-Item $example $cfgPath -Force
  & $ok "已从模板创建 config\settings.psd1"
} else {
  & $ok "config\settings.psd1 已存在，保留"
}

# 把探测到的路径写回配置（仅当当前值是占位符或路径不存在时）
$cfgText = Get-Content $cfgPath -Raw -Encoding UTF8
$needWrite = $false

if ($cfgText -match "CodebuddyCli\s*=\s*'([^']*)'") {
  $cur = $matches[1]
  if ($cur -match '[<>]' -or -not (Test-Path $cur)) {
    $cfgText = $cfgText -replace "(CodebuddyCli\s*=\s*)'[^']*'", "`$1'$($cli -replace '\\','\\')'"
    $needWrite = $true
    & $ok "已写入 CodebuddyCli（探测结果）"
  }
}

if ($cfgText -match "NodeExe\s*=\s*'([^']*)'") {
  $cur = $matches[1]
  if ($cur -and -not (Test-Path $cur)) {
    $cfgText = $cfgText -replace "(NodeExe\s*=\s*)'[^']*'", "`$1''"
    $needWrite = $true
  }
}
if ($cfgText -match "PythonExe\s*=\s*'([^']*)'") {
  $cur = $matches[1]
  if ($cur -and -not (Test-Path $cur)) {
    $cfgText = $cfgText -replace "(PythonExe\s*=\s*)'[^']*'", "`$1''"
    $needWrite = $true
  }
}

if ($needWrite) {
  [System.IO.File]::WriteAllText($cfgPath, $cfgText, (New-Object System.Text.UTF8Encoding($true)))
  & $ok "配置已更新"
}

# ---------------------------------------------------------------- 3. 图形界面
& $step "[3/5] 图形界面（可选）"

$exe = Join-Path $root 'ui\dist\WorkBuddyRelayUI\WorkBuddyRelayUI.exe'
if (Test-Path $exe) {
  & $ok "已有图形界面：$exe"
} else {
  $hasPyInstaller = $false
  $pyExe = $pythonW -replace 'pythonw\.exe$', 'python.exe'
  if (Test-Path $pyExe) {
    & $pyExe -c "import PyInstaller" 2>$null
    $hasPyInstaller = ($LASTEXITCODE -eq 0)
  }
  if (-not $hasPyInstaller) {
    & $warn "没有 PyInstaller，跳过打包图形界面（下面会建命令行快捷方式）"
    Write-Host "        想用图形界面：pip install pyinstaller pystray pillow 后重跑本脚本" -ForegroundColor DarkGray
  } else {
    Write-Host "  正在打包图形界面，约需 30-60 秒…" -ForegroundColor DarkGray
    Push-Location $root
    & $pyExe -m PyInstaller --noconfirm --onedir --noconsole --name WorkBuddyRelayUI `
      --icon "ui\app.ico" --distpath "ui\dist" --workpath "ui\build" --specpath "ui" `
      "ui\wb_bridge_ui.py" 2>&1 | Select-Object -Last 1
    Pop-Location
    Remove-Item (Join-Path $root 'ui\build') -Recurse -Force -ErrorAction SilentlyContinue
    Get-ChildItem (Join-Path $root 'ui') -Filter '*.spec' | Remove-Item -Force -ErrorAction SilentlyContinue
    if (Test-Path $exe) { & $ok "打包完成：$exe" } else { & $warn "打包失败，改用命令行快捷方式" }
  }
}

# ---------------------------------------------------------------- 4. 桌面快捷方式
& $step "[4/5] 创建桌面快捷方式"

if ($SkipShortcuts) {
  & $warn "已按参数跳过"
} else {
  $desktop = [Environment]::GetFolderPath('Desktop')
  $ws = New-Object -ComObject WScript.Shell
  $made = 0

  if (Test-Path $exe) {
    $lnk = $ws.CreateShortcut((Join-Path $desktop 'WorkBuddy中转工具.lnk'))
    $lnk.TargetPath = $exe
    $lnk.WorkingDirectory = Split-Path $exe -Parent
    $lnk.IconLocation = "$exe,0"
    $lnk.Description = "WorkBuddy -> DeepSeek Harness 中转工具"
    $lnk.Save()
    & $ok "桌面：WorkBuddy中转工具（图形界面）"
    $made++
  } else {
    $lnk = $ws.CreateShortcut((Join-Path $desktop 'WorkBuddy中转工具.lnk'))
    $lnk.TargetPath = Join-Path $root 'desktop\启动WorkBuddy中转.cmd'
    $lnk.WorkingDirectory = Join-Path $root 'desktop'
    $lnk.Description = "WorkBuddy -> DeepSeek Harness 中转工具（命令行版）"
    $lnk.Save()
    & $ok "桌面：WorkBuddy中转工具（命令行版）"
    $made++
  }

  foreach ($pair in @(
    @{ n = 'WorkBuddy中转-状态.lnk'; t = 'desktop\WorkBuddy中转状态.cmd' },
    @{ n = 'WorkBuddy中转-停止.lnk'; t = 'desktop\停止WorkBuddy中转.cmd' }
  )) {
    $target = Join-Path $root $pair.t
    if (Test-Path $target) {
      $l = $ws.CreateShortcut((Join-Path $desktop $pair.n))
      $l.TargetPath = $target
      $l.WorkingDirectory = Split-Path $target -Parent
      $l.Save()
      & $ok "桌面：$($pair.n -replace '\.lnk$','')"
      $made++
    }
  }
  Write-Host "  共创建 $made 个快捷方式（想删就删，不影响项目本身）" -ForegroundColor DarkGray
}

# ---------------------------------------------------------------- 5. 首次启动
& $step "[5/5] 首次启动"

if ($SkipStart) {
  & $warn "已按参数跳过启动"
} else {
  $startPs1 = Join-Path $root 'scripts\wb-clean-start.ps1'
  if (Test-Path $startPs1) {
    & powershell -NoProfile -ExecutionPolicy Bypass -File $startPs1
  } else {
    & $bad "找不到 scripts\wb-clean-start.ps1"
  }
}

Write-Host ""
Write-Host "=== 安装结束 ===" -ForegroundColor Cyan
Write-Host "  1. 桌面上应该有「WorkBuddy中转工具」图标，双击即可" -ForegroundColor Gray
Write-Host "  2. 使用说明：docs\GUIDE.zh-CN.md（中文） / docs\GUIDE.md（English）" -ForegroundColor Gray
Write-Host "  3. 出问题：打开界面点「复制诊断报告」，把内容发给作者" -ForegroundColor Gray
Write-Host ""
