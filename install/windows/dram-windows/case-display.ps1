# install/windows/dram-windows/case-display.ps1 - the Antec Flux Pro's temperature panel.
#
# Drives the case's side panel: CPU and GPU temperatures (decisions/log.md#d123). The panel (USB
# 2022:0522; pkgs/dram-case-display/README.md) shows nothing unless the PC sends it both
# temperatures about once a second as one 12-byte frame, and blanks itself a few seconds after
# the frames stop. This is its Windows side (Arch has its own): the CPU's Tctl and the GPU
# core from LibreHardwareMonitor's library (C:\ProgramData\dram\case-display\lhm, pinned by
# the unit case-display-lhm; the CPU needs the PawnIO driver, decisions/log.md#d124), the
# GPU from nvidia-smi when the library has none, sent as a HID output report (report ID 0 + the
# frame, padded to the panel's report length). A missing reading shows as "--.-". Run by the
# SYSTEM task dram-case-display from startup (the unit case-display-task,
# windows/hosts/cabin-win.nix); loops until stopped, reopening the panel after any error.
#   powershell -ExecutionPolicy Bypass -File case-display.ps1 [-Once]
# Log: C:\ProgramData\dram\case-display.log (start, panel found or lost, errors once each)

param([switch]$Once)
$ErrorActionPreference = 'Continue'
$log = 'C:\ProgramData\dram\case-display.log'
$lhm = 'C:\ProgramData\dram\case-display\lhm\LibreHardwareMonitorLib.dll'
$seen = @{}
function Log([string]$m) { if ($seen.ContainsKey($m)) { return }; $seen[$m] = 1; Add-Content -Path $log -Value ('{0:yyyy-MM-dd HH:mm:ss} {1}' -f (Get-Date), $m) -Encoding Ascii; if ($Once) { Write-Output $m } }

Add-Type -TypeDefinition @'
using System; using System.Runtime.InteropServices; using Microsoft.Win32.SafeHandles;
public static class DramPanel {
  [DllImport("kernel32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
  public static extern SafeFileHandle CreateFile(string name, uint access, uint share, IntPtr sa, uint disp, uint flags, IntPtr tmpl);
  [DllImport("kernel32.dll", SetLastError = true)]
  public static extern bool WriteFile(SafeFileHandle h, byte[] buf, uint len, out uint written, IntPtr ov);
  [DllImport("hid.dll")] public static extern bool HidD_GetPreparsedData(SafeFileHandle h, out IntPtr data);
  [DllImport("hid.dll")] public static extern bool HidD_FreePreparsedData(IntPtr data);
  [DllImport("hid.dll")] public static extern int HidP_GetCaps(IntPtr data, out Caps caps);
  [StructLayout(LayoutKind.Sequential)] public struct Caps {
    public ushort Usage, UsagePage, InputReportByteLength, OutputReportByteLength, FeatureReportByteLength;
    [MarshalAs(UnmanagedType.ByValArray, SizeConst = 17)] public ushort[] Reserved;
    public ushort A, B, C, D, E, F, G, H, I, J;
  }
}
'@

# 55 AA 01 01 06, CPU tens/ones/tenths, GPU tens/ones/tenths, checksum; 0xEE x3 = "--.-"
function Get-Frame($cpu, $gpu) {
  $b = New-Object System.Collections.Generic.List[int]
  foreach ($x in 0x55, 0xAA, 0x01, 0x01, 0x06) { $b.Add($x) }
  foreach ($t in $cpu, $gpu) {
    if ($null -eq $t) { $b.Add(0xEE); $b.Add(0xEE); $b.Add(0xEE); continue }
    $v = [int][math]::Max(0, [math]::Min(999, [math]::Round([double]$t * 10)))
    $b.Add([int][math]::Floor($v / 100)); $b.Add([int]([math]::Floor($v / 10) % 10)); $b.Add([int]($v % 10))
  }
  $sum = 0; foreach ($x in $b) { $sum += $x }
  $b.Add($sum -band 0xFF)
  [byte[]]$b.ToArray()
}

$script:h = $null; $script:len = 13
function Open-Panel {
  $dev = Get-PnpDevice -PresentOnly -ErrorAction SilentlyContinue | Where-Object { $_.InstanceId -match '^HID\\VID_2022&PID_0522' } | Select-Object -First 1
  if (-not $dev) { Log 'panel not found (USB 2022:0522)'; return $false }
  $p = '\\?\' + ($dev.InstanceId -replace '\\', '#') + '#{4d1e55b2-f16f-11cf-88cb-001111000030}'
  $hh = [DramPanel]::CreateFile($p, 0x40000000, 3, [IntPtr]::Zero, 3, 0, [IntPtr]::Zero)
  if ($hh.IsInvalid) { Log "panel found but not opened (error $([Runtime.InteropServices.Marshal]::GetLastWin32Error()))"; return $false }
  $pd = [IntPtr]::Zero; $caps = New-Object DramPanel+Caps
  if ([DramPanel]::HidD_GetPreparsedData($hh, [ref]$pd)) { [void][DramPanel]::HidP_GetCaps($pd, [ref]$caps); [void][DramPanel]::HidD_FreePreparsedData($pd) }
  $script:len = [math]::Max(13, [int]$caps.OutputReportByteLength)
  $script:h = $hh
  Log "panel open: $($dev.InstanceId), report length $script:len"
  return $true
}

$script:pc = $null
if (Test-Path $lhm) {
  try {
    Add-Type -Path $lhm
    $script:pc = New-Object LibreHardwareMonitor.Hardware.Computer
    $script:pc.IsCpuEnabled = $true; $script:pc.IsGpuEnabled = $true
    $script:pc.Open()
    Log 'LibreHardwareMonitor loaded'
  } catch { Log "LibreHardwareMonitor did not load: $($_.Exception.Message)"; $script:pc = $null }
} else { Log "no $lhm (converge: the unit case-display-lhm): GPU from nvidia-smi only" }

function Get-Temps {
  $cpu = $null; $gpu = $null
  if ($script:pc) {
    foreach ($hw in $script:pc.Hardware) {
      try { $hw.Update() } catch { continue }
      foreach ($s in $hw.Sensors) {
        if ([string]$s.SensorType -ne 'Temperature' -or $null -eq $s.Value) { continue }
        if ([string]$hw.HardwareType -eq 'Cpu' -and $null -eq $cpu -and $s.Name -match '^(Core \(Tctl/Tdie\)|Core \(Tctl\)|CPU Package)$') { $cpu = [double]$s.Value }
        if ([string]$hw.HardwareType -eq 'GpuNvidia' -and $null -eq $gpu -and $s.Name -eq 'GPU Core') { $gpu = [double]$s.Value }
      }
    }
    if ($null -eq $cpu) { Log 'no CPU temperature from LibreHardwareMonitor (is PawnIO installed?)' }
  }
  if ($null -eq $gpu) {
    try { $o = & "$env:windir\System32\nvidia-smi.exe" --query-gpu=temperature.gpu --format=csv,noheader,nounits 2>$null | Select-Object -First 1; if ("$o" -match '^\s*\d+') { $gpu = [double]"$o".Trim() } } catch { }
  }
  return , @($cpu, $gpu)
}

Log 'start'
while ($true) {
  if (-not $script:h -and -not (Open-Panel)) { if ($Once) { exit 1 }; Start-Sleep -Seconds 5; continue }
  $t = Get-Temps
  $f = Get-Frame $t[0] $t[1]
  $buf = New-Object byte[] $script:len; [Array]::Copy($f, 0, $buf, 1, $f.Length)
  $w = 0
  if (-not [DramPanel]::WriteFile($script:h, $buf, [uint32]$buf.Length, [ref]$w, [IntPtr]::Zero)) {
    Log "write failed (error $([Runtime.InteropServices.Marshal]::GetLastWin32Error())): reopening"
    $script:h.Close(); $script:h = $null
  }
  if ($Once) { Write-Output ('cpu {0} gpu {1} frame {2}' -f $t[0], $t[1], (($f | ForEach-Object { $_.ToString('x2') }) -join ' ')); exit 0 }
  Start-Sleep -Milliseconds 1000
}
