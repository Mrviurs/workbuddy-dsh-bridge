
# 运行时目录（本机固定 C:\temp；不存在时自动创建，避免首次运行报错）
if (-not (Test-Path 'C:\temp')) { New-Item -ItemType Directory -Force 'C:\temp' | Out-Null }
# wb-relay-stop.ps1 —— 由 desktop\停止WorkBuddy中转.cmd 或桌面快捷方式调用
# 停掉硬解三件套里的两个后台组件（自建 serve + relay），不动 WorkBuddy 本身

$ErrorActionPreference = "Continue"
$ServePort = 8791
$RelayPort = 8787
$serveTask = 'WorkBuddyCleanServe'
$relayTask = 'WorkBuddyRelay'

Write-Host ""
Write-Host "=== 停止 WorkBuddy 中转 ===" -ForegroundColor Cyan

& schtasks /end /tn $serveTask 2>&1 | Out-Null
& schtasks /end /tn $relayTask 2>&1 | Out-Null

$stopped = 0
foreach ($port in @($ServePort, $RelayPort)) {
  $l = Get-NetTCPConnection -State Listen -LocalPort $port -ErrorAction SilentlyContinue | Select-Object -First 1
  if ($l) {
    try {
      Stop-Process -Id $l.OwningProcess -Force -ErrorAction Stop
      Start-Sleep -Milliseconds 600
      Write-Host "  已停止端口 $port 上的进程 (pid $($l.OwningProcess))" -ForegroundColor Green
      $stopped++
    } catch {
      Write-Host "  端口 $port 停止失败：$($_.Exception.Message)" -ForegroundColor Red
    }
  }
}

if ($stopped -eq 0) {
  Write-Host "  中转本来就没在跑。" -ForegroundColor Yellow
}

$left = @()
foreach ($port in @($ServePort, $RelayPort)) {
  if (Get-NetTCPConnection -State Listen -LocalPort $port -ErrorAction SilentlyContinue) { $left += $port }
}
if ($left.Count -gt 0) { Write-Host "  仍被占用：$($left -join ', ')" -ForegroundColor Yellow }
else { Write-Host "  端口 $ServePort / $RelayPort 均已释放。WorkBuddy 本身不受影响。" -ForegroundColor DarkGray }

Write-Host ""
Write-Host "  想恢复：双击桌面「WorkBuddy中转工具」并点「启动 / 修复」" -ForegroundColor DarkGray
Write-Host ""
