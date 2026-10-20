# wb-doctor.ps1 —— 只读取证：查清"为什么取不到 token / 服务起不来"
#
# 用法：powershell -ExecutionPolicy Bypass -File .\scripts\wb-doctor.ps1
# 它会打印一份完整报告，同时存到 C:\temp\wb-doctor-<时间>.txt
# 出问题时把这个文件内容发给作者即可（不含 token 本身）

$ErrorActionPreference = "Continue"
$root = Split-Path -Parent $PSScriptRoot
if (-not (Test-Path 'C:\temp')) { New-Item -ItemType Directory -Force 'C:\temp' | Out-Null }

$lines = New-Object System.Collections.Generic.List[string]
function Say {
  param($text, $color = 'Gray')
  Write-Host $text -ForegroundColor $color
  $script:lines.Add($text)
}
function Section { param($t) Say "" ; Say "=== $t ===" Cyan }
function KV { param($k, $v) Say ("  {0,-22} {1}" -f $k, $v) }

Say "WorkBuddy 中转 · 诊断报告" Cyan
KV "生成时间" (Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
KV "项目目录" $root

# ---------------------------------------------------------------- 系统
Section "1. 系统环境"
$os = Get-CimInstance Win32_OperatingSystem
KV "操作系统" ("{0} (build {1})" -f $os.Caption, $os.BuildNumber)
KV "架构" $os.OSArchitecture
KV "PowerShell" $PSVersionTable.PSVersion.ToString()
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
KV "当前是否管理员" $(if ($isAdmin) { "是" } else { "否（若 WorkBuddy 以管理员运行，将读不到它的内存）" })
KV "用户" "$env:USERDOMAIN\$env:USERNAME"
KV "TEMP" $env:TEMP

# ---------------------------------------------------------------- WorkBuddy 安装
Section "2. WorkBuddy 安装位置"
$installed = @()
$searchBases = @(
  $(if ($env:LOCALAPPDATA) { Join-Path $env:LOCALAPPDATA 'Programs' }),
  $env:LOCALAPPDATA,
  $env:ProgramFiles,
  ${env:ProgramFiles(x86)},
  'D:\',
  'E:\',
  'F:\'
) | Where-Object { $_ -and (Test-Path $_) }
foreach ($base in $searchBases) {
  if (-not $base -or -not (Test-Path $base)) { continue }
  Get-ChildItem $base -Directory -Filter 'WorkBuddy*' -ErrorAction SilentlyContinue | ForEach-Object {
    $exe = Join-Path $_.FullName 'WorkBuddy.exe'
    if (Test-Path $exe) { $installed += $exe }
  }
}
$installed = @($installed | Select-Object -Unique)   # 必须强制数组，否则单元素会退化成字符串
if ($installed.Count -eq 0) {
  Say "  未在常见位置找到 WorkBuddy.exe" Yellow
  Say "  如果你的安装在别处，请忽略这一项（本报告后续不依赖它）" DarkGray
} else {
  foreach ($exe in $installed) {
    $ver = (Get-Item $exe).VersionInfo
    KV "安装路径" $exe
    KV "  版本" ("{0} (file {1})" -f $ver.ProductVersion, $ver.FileVersion)
  }
}
$cli = $null
if ($installed.Count -gt 0) {
  $c = Join-Path (Split-Path $installed[0] -Parent) 'resources\app.asar.unpacked\cli\bin\codebuddy'
  if (Test-Path $c) { $cli = $c; KV "CLI" $c } else { Say "  同目录下没找到 codebuddy CLI" Yellow }
}

# ---------------------------------------------------------------- 候选进程
Section "3. 相关进程（这是最关键的一节）"
$procs = @()
try {
  $procs = Get-CimInstance Win32_Process -ErrorAction Stop | Where-Object {
    ($_.Name -match '^(WorkBuddy|CodeBuddy|codebuddy)') -or
    ($_.Name -match '^node' -and $_.CommandLine -and $_.CommandLine -match 'codebuddy|workbuddy')
  } | Sort-Object CreationDate -Descending
} catch {
  Say "  枚举进程失败：$($_.Exception.Message)" Red
}

if ($procs.Count -eq 0) {
  Say "  [!!] 没有任何 WorkBuddy / CodeBuddy / 带 codebuddy 命令行的 node 进程" Red
  Say "       这说明：WorkBuddy 可能没在运行，或者它拉起的 CLI 进程名不在上述范围" Yellow
  Say "       请把这份报告发给作者，我需要看真实的进程名" Yellow
} else {
  Say "  共 $($procs.Count) 个候选进程：" Green
  foreach ($p in $procs) {
    $cl = if ($p.CommandLine) { $p.CommandLine } else { '(无法读取命令行，通常意味着权限不足)' }
    if ($cl.Length -gt 160) { $cl = $cl.Substring(0, 160) + '…' }
    Say ""
    Say ("  --- pid {0}  {1}" -f $p.ProcessId, $p.Name) White
    Say ("      内存      : {0:N0} MB" -f ($p.WorkingSetSize / 1MB))
    Say ("      启动时间  : {0}" -f $p.CreationDate)
    Say ("      含 --serve: {0}" -f $(if ($p.CommandLine -and $p.CommandLine -match '--serve') { '是' } else { '否' }))
    Say ("      命令行    : {0}" -f $cl)
  }
}

# ---------------------------------------------------------------- 权限测试
Section "4. 能否读取这些进程（权限）"
Add-Type -Namespace WBDoc -Name Native -MemberDefinition @'
[DllImport("kernel32.dll", SetLastError=true)]
public static extern IntPtr OpenProcess(uint access, bool inherit, int pid);
[DllImport("kernel32.dll", SetLastError=true)]
public static extern bool CloseHandle(IntPtr h);
'@ -ErrorAction SilentlyContinue

foreach ($p in $procs) {
  $h = [WBDoc.Native]::OpenProcess(0x0410, $false, [int]$p.ProcessId)   # QUERY_INFORMATION | VM_READ
  if ($h -ne [IntPtr]::Zero) {
    [void][WBDoc.Native]::CloseHandle($h)
    Say ("  pid {0,-7} 可读" -f $p.ProcessId) Green
  } else {
    $err = [Runtime.InteropServices.Marshal]::GetLastWin32Error()
    Say ("  pid {0,-7} 不可读（Win32 错误 {1}）—— 需要管理员权限" -f $p.ProcessId, $err) Red
  }
}

# ---------------------------------------------------------------- 内存扫描
Section "5. 内存里能不能扫到 JWT"
$scanPs1 = Join-Path $PSScriptRoot 'wb-scan-token.ps1'
if (-not (Test-Path $scanPs1)) {
  Say "  找不到 wb-scan-token.ps1，跳过" Yellow
} else {
  foreach ($p in $procs) {
    Say ""
    Say ("  --- 扫描 pid {0} ({1})" -f $p.ProcessId, $p.Name) White
    Remove-Item 'C:\temp\wb-mem-candidates.txt' -Force -ErrorAction SilentlyContinue
    & $scanPs1 -ProcessId $p.ProcessId -MaxMB 2048 6>$null | Out-Null
    if (Test-Path 'C:\temp\wb-mem-candidates.txt') {
      $mem = Get-Content 'C:\temp\wb-mem-candidates.txt' -Encoding UTF8
      $jwtHit = $mem | Where-Object { $_ -match '^bearer\teyJ' }
      if ($jwtHit) {
        $len = (($jwtHit | Sort-Object Length -Descending | Select-Object -First 1) -replace '^[^\t]+\t','').Length
        Say ("      找到 JWT（长度 {0}）—— 这个进程就是我们要的" -f $len) Green
      } else {
        $cnt = ($mem | Measure-Object).Count
        Say ("      有 {0} 条候选记录，但没有 eyJ 开头的 JWT" -f $cnt) Yellow
        $mem | Select-Object -First 8 | ForEach-Object {
          $short = if ($_.Length -gt 100) { $_.Substring(0, 100) + '…' } else { $_ }
          Say ("        {0}" -f $short) DarkGray
        }
      }
    } else {
      Say "      扫描没有产出（权限不足或进程已退出）" Red
    }
  }
}

# ---------------------------------------------------------------- 缓存与配置
Section "6. 本地状态"
$jwtPath = 'C:\temp\wb-jwt.txt'
if (Test-Path $jwtPath) {
  $tok = (Get-Content $jwtPath -Raw).Trim()
  $expTxt = '无法解析'
  try {
    $payload = $tok.Split('.')[1]
    $payload = $payload.Replace('-', '+').Replace('_', '/')
    switch ($payload.Length % 4) { 2 { $payload += '==' } 3 { $payload += '=' } }
    $json = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($payload)) | ConvertFrom-Json
    $expTxt = ([datetimeoffset]::FromUnixTimeSeconds([int64]$json.exp)).LocalDateTime.ToString('yyyy-MM-dd HH:mm:ss')
  } catch { }
  KV "缓存 token" ("len={0}  过期={1}" -f $tok.Length, $expTxt)
} else {
  KV "缓存 token" "不存在（正常，首次运行时生成）"
}

$cfg = Join-Path $root 'config\settings.psd1'
if (Test-Path $cfg) {
  try {
    $S = Import-PowerShellDataFile $cfg
    KV "CodebuddyCli" $S.CodebuddyCli
    KV "  CLI 是否存在" $(if (Test-Path $S.CodebuddyCli) { '是' } else { '否  ← 要在 settings.psd1 里改' })
    KV "NodeExe" $(if ($S.NodeExe) { $S.NodeExe } else { '(自动探测)' })
    KV "PythonExe" $(if ($S.PythonExe) { $S.PythonExe } else { '(自动探测)' })
  } catch {
    KV "settings.psd1" "解析失败：$($_.Exception.Message)"
  }
} else {
  KV "settings.psd1" "不存在（尚未运行一键安装）"
}

# ---------------------------------------------------------------- 服务
Section "7. 服务与任务"
foreach ($pair in @(@{ p = 8791; n = 'serve' }, @{ p = 8787; n = 'relay' })) {
  $listen = Get-NetTCPConnection -State Listen -LocalPort $pair.p -ErrorAction SilentlyContinue | Select-Object -First 1
  if ($listen) { KV ("端口 " + $pair.p + " (" + $pair.n + ")") ("监听中，pid " + $listen.OwningProcess) } else { KV ("端口 " + $pair.p + " (" + $pair.n + ")") "未监听" }
}
foreach ($t in @('WorkBuddyCleanServe', 'WorkBuddyRelay')) {
  $st = & schtasks /query /tn $t /fo LIST 2>$null | Select-String 'Status|状态'
  KV ("任务 " + $t) $(if ($st) { ($st -split ':', 2)[-1].Trim() } else { '不存在' })
}

# ---------------------------------------------------------------- 结论
Section "8. 结论"
if ($procs.Count -eq 0) {
  Say "  · 没有候选进程 → 请确认 WorkBuddy 真的在运行；若确实在运行，把本报告发给作者" Yellow
} else {
  $serveProc = $procs | Where-Object { $_.CommandLine -and $_.CommandLine -match '--serve' } | Select-Object -First 1
  if ($serveProc) {
    Say ("  · 找到 serve 进程：pid {0}" -f $serveProc.ProcessId) Green
  } else {
    Say "  · 有候选进程，但没有一个命令行含 --serve" Yellow
    Say "    这说明这台机器的 WorkBuddy 可能用别的方式启动 CLI —— 需要看第 5 节哪个进程里有 JWT" Yellow
  }
}
if (-not $isAdmin) {
  Say "  · 当前非管理员：若第 4 节出现「不可读」，请以管理员身份重跑本脚本" Yellow
}

# ---------------------------------------------------------------- 落盘
$out = Join-Path 'C:\temp' ("wb-doctor-{0}.txt" -f (Get-Date -Format 'yyyyMMdd-HHmmss'))
$lines -join "`r`n" | Set-Content -Path $out -Encoding UTF8
Say ""
Say "报告已保存：$out" Cyan
Say "（内容不含 token 本身，可以直接发给作者）" DarkGray
