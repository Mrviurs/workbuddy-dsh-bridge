param([Parameter(Mandatory=$true)][int]$ProcessId, [switch]$Everything)


# 运行时目录（本机固定 C:\temp；不存在时自动创建，避免首次运行报错）
if (-not (Test-Path 'C:\temp')) { New-Item -ItemType Directory -Force 'C:\temp' | Out-Null }
$src = @"
using System;
using System.Text;
using System.Collections.Generic;
using System.Runtime.InteropServices;

public static class PebScan {
    [StructLayout(LayoutKind.Sequential)]
    public struct PBI {
        public IntPtr Reserved1; public IntPtr PebBaseAddress;
        public IntPtr R2a; public IntPtr R2b;
        public IntPtr UniqueProcessId; public IntPtr R3;
    }
    [DllImport("kernel32.dll", SetLastError=true)] public static extern IntPtr OpenProcess(uint a, bool i, int pid);
    [DllImport("kernel32.dll", SetLastError=true)] public static extern bool ReadProcessMemory(IntPtr h, IntPtr addr, byte[] buf, IntPtr size, out IntPtr read);
    [DllImport("kernel32.dll")] public static extern bool CloseHandle(IntPtr h);
    [DllImport("ntdll.dll")] public static extern int NtQueryInformationProcess(IntPtr h, int c, ref PBI i, int l, out int r);

    static int ReadI(IntPtr h, long addr, byte[] buf, int len) {
        int off = 0;
        while (off < len) {
            int chunk = Math.Min(2048, len - off);
            byte[] tmp = new byte[chunk]; IntPtr r2;
            if (!ReadProcessMemory(h, (IntPtr)(addr + off), tmp, (IntPtr)chunk, out r2)) break;
            Buffer.BlockCopy(tmp, 0, buf, off, chunk); off += chunk;
        }
        return off;
    }

    // 判断一段内存是否是 NAME=VALUE 形式的环境块
    static bool LooksLikeEnv(IntPtr h, long addr, out string text, out int len) {
        text = null; len = 0;
        byte[] buf = new byte[32768];
        int got = ReadI(h, addr, buf, buf.Length);
        if (got < 8) return false;
        string s = Encoding.Unicode.GetString(buf, 0, got);
        int z = s.IndexOf("\0\0", StringComparison.Ordinal);
        if (z > 0) s = s.Substring(0, z);
        int ok = 0, eq = 0, tot = 0;
        foreach (char c in s) {
            tot++;
            if (c == '=') eq++;
            if (c >= 0x20 && c < 0x7f || c == '\0' || c == '=' || c == ';' || c == '\\' || c == '/' || c == ':' || c == '_' || c == '-' || c == '.' || c == '(' || c == ')' || c == ',' || c == ' ' || c == '%' || c == '"') ok++;
        }
        if (tot < 16) return false;
        if (eq < 3) return false;
        if (ok * 100 / tot < 90) return false;
        text = s; len = s.Length; return true;
    }

    public static string[] Scan(int pid, out string diag) {
        diag = "";
        IntPtr h = OpenProcess(0x0410, false, pid);
        if (h == IntPtr.Zero) { diag = "OpenProcess=" + Marshal.GetLastWin32Error(); return null; }
        try {
            PBI pbi = new PBI(); int ret;
            int st = NtQueryInformationProcess(h, 0, ref pbi, Marshal.SizeOf(pbi), out ret);
            if (st != 0) { diag = "NtQuery=" + st; return null; }
            byte[] peb = new byte[0x400]; IntPtr read;
            if (!ReadProcessMemory(h, pbi.PebBaseAddress, peb, (IntPtr)peb.Length, out read)) { diag = "PEB=" + Marshal.GetLastWin32Error(); return null; }

            // 兼容 x64(0x20) 与 x86(0x10) 两种 ProcessParameters 位置
            long[] ppCandidates = new long[2];
            ppCandidates[0] = BitConverter.ToInt64(peb, 0x20);
            ppCandidates[1] = BitConverter.ToInt64(peb, 0x10);
            List<string> found = new List<string>();

            foreach (long ppAddr in ppCandidates) {
                if (ppAddr < 0x1000) continue;
                byte[] pp = new byte[0x400];
                if (!ReadProcessMemory(h, (IntPtr)ppAddr, pp, (IntPtr)pp.Length, out read)) continue;
                diag += String.Format("pp=0x{0:X} read={1} ", ppAddr, (int)read);
                // 遍历每个 8 字节指针槽，找能读出环境块的那个
                for (int off = 0x40; off < 0x300; off += 8) {
                    long ptr = BitConverter.ToInt64(pp, off);
                    if (ptr < 0x10000 || ptr > 0x7FFFFFFFFFFF) continue;
                    string text; int len;
                    if (LooksLikeEnv(h, ptr, out text, out len)) {
                        diag += String.Format("hit@0x{0:X}(len={1}) ", off, len);
                        found.Add(text);
                        if (found.Count >= 2) break;
                    }
                }
                if (found.Count > 0) break;
            }
            return found.ToArray();
        } finally { CloseHandle(h); }
    }
}
"@

Add-Type -TypeDefinition $src -Language CSharp

$diag = $null
$blocks = [PebScan]::Scan($ProcessId, [ref]$diag)
Write-Host "diag: $diag" -ForegroundColor DarkGray
if (-not $blocks -or $blocks.Count -eq 0) { Write-Host "未定位到环境块" -ForegroundColor Red; exit 1 }

$all = @()
foreach ($b in $blocks) { $all += ($b -split "`0" | Where-Object { $_ -match '=' }) }
$uniq = $all | Sort-Object -Unique
Write-Host "环境变量总数: $($uniq.Count)" -ForegroundColor DarkGray

if ($Everything) { $interesting = $uniq } else { $interesting = $uniq | Where-Object { $_ -match '^(CODEBUDDY_|ANTHROPIC_|OPENAI_|WB_|WORKBUDDY_)' } }
foreach ($v in $interesting) {
  $name = $v.Split('=')[0]; $val = $v.Substring($name.Length + 1)
  if ($name -match 'TOKEN|KEY|SECRET|PASSWORD') {
    $show = if ($val.Length -gt 16) { $val.Substring(0,10) + "…" + $val.Substring($val.Length-4) + " (len=$($val.Length))" } else { "(len=$($val.Length))" }
    Write-Host ("{0} = {1}" -f $name, $show) -ForegroundColor Yellow
  } else {
    $show = if ($val.Length -gt 170) { $val.Substring(0,170) + "…" } else { $val }
    Write-Host ("{0} = {1}" -f $name, $show)
  }
}

$dump = $uniq | Where-Object { $_ -match '^(CODEBUDDY_AUTH_TOKEN|CODEBUDDY_API_KEY|CODEBUDDY_GATEWAY_PASSWORD|WORKBUDDY_VLM_AUTH_TOKEN|WORKBUDDY_VLM_CHAT_URL|WORKBUDDY_VLM_MODEL|WORKBUDDY_VLM_CONTEXT)=' }
if ($dump) { New-Item -ItemType Directory -Force C:\temp | Out-Null; $dump | Set-Content C:\temp\wb-cli-env.txt -Encoding ascii; Write-Host "`n敏感值已写入 C:\temp\wb-cli-env.txt" -ForegroundColor Green }
