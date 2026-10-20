param(
  [Parameter(Mandatory=$true)][int]$ProcessId,
  [int]$MaxMB = 2048
)

$src = @"
using System;
using System.Text;
using System.Collections.Generic;
using System.Runtime.InteropServices;
using System.Text.RegularExpressions;

public static class MemScan {
    [StructLayout(LayoutKind.Sequential)]
    public struct MBI {
        public ulong BaseAddress;
        public ulong AllocationBase;
        public uint AllocationProtect;
        public uint Alignment1;
        public ulong RegionSize;
        public uint State;
        public uint Protect;
        public uint Type;
        public uint Alignment2;
    }

    [DllImport("kernel32.dll", SetLastError=true)]
    public static extern IntPtr OpenProcess(uint access, bool inherit, int pid);
    [DllImport("kernel32.dll", SetLastError=true)]
    public static extern bool ReadProcessMemory(IntPtr h, IntPtr addr, byte[] buf, IntPtr size, out IntPtr read);
    [DllImport("kernel32.dll")]
    public static extern bool CloseHandle(IntPtr h);
    [DllImport("kernel32.dll", SetLastError=true)]
    public static extern IntPtr VirtualQueryEx(IntPtr h, IntPtr addr, out MBI mbi, IntPtr len);

    static readonly Regex ReBearer = new Regex(@"Bearer[ \t]+([A-Za-z0-9._\-=+/]{20,4000})", RegexOptions.Compiled);
    static readonly Regex ReAccess = new Regex(@"""access_?[Tt]oken""\s*:\s*""([^""]{20,4000})""", RegexOptions.Compiled);
    static readonly Regex ReRefresh = new Regex(@"""refresh_?[Tt]oken""\s*:\s*""([^""]{20,400})""", RegexOptions.Compiled);
    static readonly Regex ReToken = new Regex(@"""token""\s*:\s*""([A-Za-z0-9._\-=+/]{20,4000})""", RegexOptions.Compiled);

    static void Collect(Regex re, string s, Dictionary<string,int> bag, string tag) {
        foreach (Match m in re.Matches(s)) {
            string v = m.Groups[1].Value.Trim();
            if (v.Length < 20) continue;
            string key = tag + "|" + v;
            if (bag.ContainsKey(key)) bag[key] = bag[key] + 1;
            else if (bag.Count < 400) bag[key] = 1;
        }
    }

    public static string[] Scan(int pid, long maxBytes, out string diag) {
        diag = "";
        IntPtr h = OpenProcess(0x0410, false, pid);
        if (h == IntPtr.Zero) { diag = "OpenProcess failed: " + Marshal.GetLastWin32Error(); return null; }

        var bag = new Dictionary<string, int>();
        long scanned = 0, regions = 0;
        MBI mbi;
        int mbiSize = Marshal.SizeOf(typeof(MBI));
        ulong addr = 0;

        try {
            while (scanned < maxBytes) {
                if (VirtualQueryEx(h, (IntPtr)(long)addr, out mbi, (IntPtr)mbiSize) == IntPtr.Zero) break;
                if (mbi.RegionSize == 0) break;

                bool readable = (mbi.State == 0x1000)                       // MEM_COMMIT
                    && ((mbi.Protect & 0x01) == 0)                          // 非 PAGE_NOACCESS
                    && ((mbi.Protect & 0x100) == 0);                        // 非 PAGE_GUARD

                if (readable && mbi.RegionSize <= 256L * 1024 * 1024) {
                    long regionLeft = (long)mbi.RegionSize;
                    long off = 0;
                    const int CHUNK = 1 << 20;                              // 1MB
                    while (regionLeft > 0) {
                        int want = (int)Math.Min(CHUNK, regionLeft);
                        byte[] buf = new byte[want];
                        IntPtr read;
                        if (!ReadProcessMemory(h, (IntPtr)((long)mbi.BaseAddress + off), buf, (IntPtr)want, out read)) break;
                        int got = (int)read;
                        if (got > 0) {
                            string s = Encoding.GetEncoding(28591).GetString(buf, 0, got);
                            Collect(ReBearer, s, bag, "bearer");
                            Collect(ReAccess, s, bag, "access");
                            Collect(ReRefresh, s, bag, "refresh");
                            Collect(ReToken, s, bag, "token");
                            scanned += got;
                        }
                        off += want;
                        regionLeft -= want;
                        if (scanned >= maxBytes) break;
                    }
                    regions++;
                }
                ulong next = mbi.BaseAddress + mbi.RegionSize;
                if (next <= addr) break;
                addr = next;
            }
        } finally { CloseHandle(h); }

        diag = string.Format("扫描 {0:N1} MB / {1} 个区域", scanned / 1048576.0, regions);
        var outp = new List<string>();
        foreach (var kv in bag) outp.Add(kv.Key + "|" + kv.Value);
        return outp.ToArray();
    }
}
"@

Add-Type -TypeDefinition $src -Language CSharp

$diag = $null
$rows = [MemScan]::Scan($ProcessId, [long]$MaxMB * 1MB, [ref]$diag)
Write-Host "diag: $diag" -ForegroundColor DarkGray
if (-not $rows -or $rows.Count -eq 0) { Write-Host "没有命中" -ForegroundColor Red; exit 1 }

$parsed = $rows | ForEach-Object {
  $p = $_.Split('|')
  [pscustomobject]@{ Tag = $p[0]; Value = $p[1]; Hits = [int]$p[2] }
}

$parsed = $parsed | Sort-Object Tag, @{Expression='Hits';Descending=$true}
Write-Host "候选总数: $($parsed.Count)"
$parsed | ForEach-Object {
  $v = $_.Value
  $show = if ($v.Length -gt 24) { $v.Substring(0,12) + "…" + $v.Substring($v.Length-6) } else { $v }
  "{0,-8} len={1,-4} hits={2,-3} {3}" -f $_.Tag, $v.Length, $_.Hits, $show
}

New-Item -ItemType Directory -Force C:\temp | Out-Null
$parsed | ForEach-Object { $_.Tag + "`t" + $_.Value } | Set-Content C:\temp\wb-mem-candidates.txt -Encoding ascii
Write-Host "`n候选已写入 C:\temp\wb-mem-candidates.txt" -ForegroundColor Green
