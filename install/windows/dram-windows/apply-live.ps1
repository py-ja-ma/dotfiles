# install/windows/dram-windows/apply-live.ps1 - the converged look on the desktop now, not at
# the next sign-in.
#
# The converge runs over SSH: what it writes lands in the registry, but the signed-in desktop
# rereads some of it only when told. This tells it: the pointer scheme (SPI_SETCURSORS), the
# caret width, the language toggle (SPI_SETLANGTOGGLE), dark mode and the accent
# (WM_SETTINGCHANGE "ImmersiveColorSet"), the environment (STARSHIP_CONFIG: "Environment"),
# the house fonts (AddFontResource for this session + WM_FONTCHANGE), each display's highest
# refresh rate at its resolution (only the desktop session can see the displays), the taskbar
# auto-hidden (Explorer's own switch, asked on its desktop), and the masthead: Zebar started, or
# restarted when its pack is newer than it. converge.ps1 starts it
# in the signed-in user's session, as a one-off task with that user's token (the way
# debloat.ps1 opens an uninstaller there); hidden by conhost --headless, since Windows
# Terminal would otherwise host its console. Writes apply-live.log beside it.
#   powershell -ExecutionPolicy Bypass -File C:\ProgramData\dram\apply-live.ps1

$ErrorActionPreference = 'Continue'
$Here = Split-Path -Parent $MyInvocation.MyCommand.Path
Add-Type -Namespace Dram -Name Live -MemberDefinition @'
[DllImport("user32.dll", SetLastError = true)]
public static extern bool SystemParametersInfo(uint action, uint uiParam, IntPtr pvParam, uint winIni);
[DllImport("user32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
public static extern IntPtr SendMessageTimeout(IntPtr hWnd, uint msg, UIntPtr wParam, string lParam, uint flags, uint timeout, out UIntPtr result);
[DllImport("gdi32.dll", CharSet = CharSet.Unicode)]
public static extern int AddFontResource(string file);
'@
$send = 3                     # SPIF_UPDATEINIFILE | SPIF_SENDCHANGE
$all = [IntPtr]0xffff         # HWND_BROADCAST
$r = [UIntPtr]::Zero
$done = @()
# SPI_SETCURSORS reloads the scheme the registry already holds: with SPIF_UPDATEINIFILE it fails
# (FALSE, no error; cabin 2026-10-12), so the pointer only changed at the next sign-in
if ([Dram.Live]::SystemParametersInfo(0x57, 0, [IntPtr]::Zero, 0)) { $done += 'pointer' }             # SPI_SETCURSORS
if ([Dram.Live]::SystemParametersInfo(0x2007, 0, [IntPtr]2, $send)) { $done += 'caret' }              # SPI_SETCARETWIDTH
if ([Dram.Live]::SystemParametersInfo(0x5B, 0, [IntPtr]::Zero, $send)) { $done += 'language toggle' } # SPI_SETLANGTOGGLE
$faces = 0
$winFonts = Join-Path $env:windir 'Fonts'
foreach ($f in @(Get-ChildItem -LiteralPath (Join-Path $Here 'fonts') -File -ErrorAction SilentlyContinue | Where-Object { $_.Extension -match '^\.(otf|ttf)$' })) {
  $t = Join-Path $winFonts $f.Name
  if (Test-Path -LiteralPath $t) { $faces += [Dram.Live]::AddFontResource($t) }
}
foreach ($what in 'ImmersiveColorSet', 'WindowsThemeElement', 'Environment') {
  [void][Dram.Live]::SendMessageTimeout($all, 0x1A, [UIntPtr]::Zero, $what, 2, 5000, [ref]$r)   # WM_SETTINGCHANGE, SMTO_ABORTIFHUNG
}
[void][Dram.Live]::SendMessageTimeout($all, 0x1D, [UIntPtr]::Zero, $null, 2, 5000, [ref]$r)       # WM_FONTCHANGE
$done += 'colours', 'environment', "$faces font face(s)"

# Each display at the highest refresh rate it offers AT ITS CURRENT RESOLUTION, as Arch's
# hyprland.lua declares cabin's NZXT panels (165 Hz on DisplayPort, 144 on HDMI; Windows had
# left both at 59). Never a lower resolution for a higher rate: Hyprland's "highrr" did that
# and dropped the desktop to 1920x1080 (2026-10-05). Saved to the registry, so it holds.
Add-Type -TypeDefinition @'
using System; using System.Runtime.InteropServices;
public static class DramDisplay {
  [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)] public struct DISPLAY_DEVICE {
    public int cb; [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 32)] public string DeviceName;
    [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 128)] public string DeviceString; public int StateFlags;
    [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 128)] public string DeviceID;
    [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 128)] public string DeviceKey; }
  [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)] public struct DEVMODE {
    [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 32)] public string dmDeviceName;
    public short dmSpecVersion, dmDriverVersion, dmSize, dmDriverExtra; public int dmFields, dmPositionX, dmPositionY, dmDisplayOrientation, dmDisplayFixedOutput;
    public short dmColor, dmDuplex, dmYResolution, dmTTOption, dmCollate;
    [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 32)] public string dmFormName;
    public short dmLogPixels; public int dmBitsPerPel, dmPelsWidth, dmPelsHeight, dmDisplayFlags, dmDisplayFrequency, dmICMMethod, dmICMIntent, dmMediaType, dmDitherType, dmReserved1, dmReserved2, dmPanningWidth, dmPanningHeight; }
  [DllImport("user32.dll", CharSet = CharSet.Unicode)] public static extern bool EnumDisplayDevices(string dev, int i, ref DISPLAY_DEVICE dd, int flags);
  [DllImport("user32.dll", CharSet = CharSet.Unicode)] public static extern bool EnumDisplaySettings(string dev, int mode, ref DEVMODE dm);
  [DllImport("user32.dll", CharSet = CharSet.Unicode)] public static extern int ChangeDisplaySettingsEx(string dev, ref DEVMODE dm, IntPtr hwnd, int flags, IntPtr param);
}
'@
for ($i = 0; $i -lt 16; $i++) {
  $dd = New-Object DramDisplay+DISPLAY_DEVICE; $dd.cb = [Runtime.InteropServices.Marshal]::SizeOf($dd)
  # [NullString]: PowerShell passes a plain $null to a string parameter as "", which matches no device
  if (-not [DramDisplay]::EnumDisplayDevices([NullString]::Value, $i, [ref]$dd, 0)) { break }
  if (($dd.StateFlags -band 1) -eq 0) { continue }                                  # not on the desktop
  $cur = New-Object DramDisplay+DEVMODE; $cur.dmSize = [Runtime.InteropServices.Marshal]::SizeOf($cur)
  if (-not [DramDisplay]::EnumDisplaySettings($dd.DeviceName, -1, [ref]$cur)) { continue }   # ENUM_CURRENT_SETTINGS
  $m = New-Object DramDisplay+DEVMODE; $m.dmSize = $cur.dmSize
  $best = $cur.dmDisplayFrequency
  for ($j = 0; [DramDisplay]::EnumDisplaySettings($dd.DeviceName, $j, [ref]$m); $j++) {
    if ($m.dmPelsWidth -eq $cur.dmPelsWidth -and $m.dmPelsHeight -eq $cur.dmPelsHeight -and $m.dmBitsPerPel -eq $cur.dmBitsPerPel -and
      ($m.dmDisplayFlags -band 2) -eq 0 -and $m.dmDisplayFrequency -gt $best) { $best = $m.dmDisplayFrequency }   # not DM_INTERLACED
  }
  if ($best -le $cur.dmDisplayFrequency) { continue }
  $was = $cur.dmDisplayFrequency
  $cur.dmDisplayFrequency = $best; $cur.dmFields = 0x400000                         # DM_DISPLAYFREQUENCY
  $rc = [DramDisplay]::ChangeDisplaySettingsEx($dd.DeviceName, [ref]$cur, [IntPtr]::Zero, 1, [IntPtr]::Zero)   # CDS_UPDATEREGISTRY
  $done += ('{0} {1}x{2} {3} -> {4} Hz{5}' -f $dd.DeviceName.TrimStart('\', '.'), $cur.dmPelsWidth, $cur.dmPelsHeight, $was, $best, $(if ($rc -ne 0) { " (failed: $rc)" } else { '' }))
}

# The taskbar auto-hidden at the bottom, under the masthead: the switch Settings flips
# (SHAppBarMessage ABM_SETSTATE with ABS_AUTOHIDE; Explorer keeps it in StuckRects3), read back with
# ABM_GETSTATE. 26H2 auto-hides only a bottom taskbar, which is Windows' default edge.
# The taskbar is the Shell_TrayWnd window Explorer owns: Zebar's tray adds a second of that class.
Add-Type -TypeDefinition @'
using System; using System.Runtime.InteropServices; using System.Text;
public static class DramBar {
  [StructLayout(LayoutKind.Sequential)] public struct RECT { public int Left, Top, Right, Bottom; }
  [StructLayout(LayoutKind.Sequential)] public struct APPBARDATA {
    public int cbSize; public IntPtr hWnd; public uint uCallbackMessage; public uint uEdge; public RECT rc; public IntPtr lParam; }
  [DllImport("shell32.dll")] public static extern UIntPtr SHAppBarMessage(uint msg, ref APPBARDATA data);
  [DllImport("user32.dll", CharSet = CharSet.Unicode)] public static extern IntPtr FindWindowEx(IntPtr parent, IntPtr after, string cls, string title);
  [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint pid);
  public delegate bool EnumProc(IntPtr hWnd, IntPtr lParam);
  [DllImport("user32.dll")] public static extern bool EnumWindows(EnumProc fn, IntPtr lParam);
  [DllImport("user32.dll", CharSet = CharSet.Unicode)] public static extern int GetWindowText(IntPtr hWnd, StringBuilder text, int max);
  [DllImport("user32.dll")] public static extern bool PostMessage(IntPtr hWnd, uint msg, IntPtr wParam, IntPtr lParam);
  // WM_CLOSE to each top-level window of the process whose title starts with the prefix
  public static int Close(uint pid, string prefix) {
    int n = 0;
    EnumWindows(delegate (IntPtr h, IntPtr l) {
      uint p; GetWindowThreadProcessId(h, out p);
      if (p != pid) return true;
      StringBuilder t = new StringBuilder(256); GetWindowText(h, t, 256);
      if (t.ToString().StartsWith(prefix, StringComparison.Ordinal)) { PostMessage(h, 0x10, IntPtr.Zero, IntPtr.Zero); n++; }
      return true;
    }, IntPtr.Zero);
    return n;
  }
}
'@
$tray = [IntPtr]::Zero
$h = [IntPtr]::Zero
while ($true) {
  # [NullString]: a plain $null would reach the title parameter as "", which is a title to match
  $h = [DramBar]::FindWindowEx([IntPtr]::Zero, $h, 'Shell_TrayWnd', [NullString]::Value)
  if ($h -eq [IntPtr]::Zero) { break }
  $tp = [uint32]0
  [void][DramBar]::GetWindowThreadProcessId($h, [ref]$tp)
  $pn = $null
  try { $pn = (Get-Process -Id $tp -ErrorAction Stop).ProcessName } catch { }
  if ($pn -eq 'explorer') { $tray = $h; break }
}
if ($tray -eq [IntPtr]::Zero) { $done += 'taskbar auto-hide: no taskbar (Explorer not running)' }
else {
  $ab = New-Object DramBar+APPBARDATA
  $ab.cbSize = [Runtime.InteropServices.Marshal]::SizeOf($ab)
  $ab.hWnd = $tray
  $st = [DramBar]::SHAppBarMessage(4, [ref]$ab).ToUInt32()            # ABM_GETSTATE
  if (($st -band 1) -ne 0) { $done += 'taskbar auto-hide on' }
  else {
    $ab.lParam = [IntPtr]([int]($st -bor 1))                           # ABS_AUTOHIDE, ABS_ALWAYSONTOP as it was
    [void][DramBar]::SHAppBarMessage(10, [ref]$ab)                     # ABM_SETSTATE
    $st = [DramBar]::SHAppBarMessage(4, [ref]$ab).ToUInt32()
    $done += $(if (($st -band 1) -ne 0) { 'taskbar auto-hide off -> on' } else { 'taskbar auto-hide: Explorer kept it shown' })
  }
}

# The masthead on this desktop now (at sign-in, Zebar's Run entry starts it): started when Zebar is
# installed and declared but not running; restarted when look.ps1 wrote a newer pack than the one it
# read at start. Its widget windows close first, so each hands back the edge it reserved (a killed
# process would leave the space taken). Started through Explorer, as Run starts it: outside this
# one-off task, whose below-normal priority it would inherit and whose end could take it along.
$zebar = Join-Path $env:ProgramFiles 'glzr.io\Zebar\zebar.exe'
$zdir = Join-Path $env:USERPROFILE '.glzr\zebar'
$zrun = $null
try { $zrun = Get-ItemPropertyValue -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run' -Name Zebar -ErrorAction Stop } catch { }
if ((Test-Path -LiteralPath $zebar) -and $zrun -and (Test-Path -LiteralPath (Join-Path $zdir 'letterpress\zpack.json'))) {
  $session = [Diagnostics.Process]::GetCurrentProcess().SessionId
  $zp = @(Get-Process -Name zebar -ErrorAction SilentlyContinue | Where-Object { $_.SessionId -eq $session })
  $files = @(Get-Item -LiteralPath (Join-Path $zdir 'settings.json') -ErrorAction SilentlyContinue) + @(Get-ChildItem -LiteralPath (Join-Path $zdir 'letterpress') -File -ErrorAction SilentlyContinue)
  $newest = ($files | Sort-Object LastWriteTime | Select-Object -Last 1).LastWriteTime
  $how = ''
  if ($zp.Count -eq 0) { $how = 'started' }
  elseif ($newest -gt ($zp | Sort-Object StartTime | Select-Object -First 1).StartTime) {
    foreach ($q in $zp) { [void][DramBar]::Close([uint32]$q.Id, 'Zebar - ') }
    Start-Sleep -Seconds 2
    $zp | Stop-Process -Force -ErrorAction SilentlyContinue
    $zp | Wait-Process -Timeout 10 -ErrorAction SilentlyContinue
    $how = 'restarted for its new pack'
  }
  if (-not $how) { $done += 'masthead running' }
  else {
    if ($tray -ne [IntPtr]::Zero) { Start-Process -FilePath (Join-Path $env:windir 'explorer.exe') -ArgumentList ('"{0}"' -f $zebar) }
    else { Start-Process -FilePath $zebar -ArgumentList 'startup' }
    $up = $false
    for ($i = 0; $i -lt 20 -and -not $up; $i++) { Start-Sleep -Milliseconds 500; $up = [bool](Get-Process -Name zebar -ErrorAction SilentlyContinue) }
    $done += $(if ($up) { "masthead $how" } else { 'masthead: Zebar did not start (see .glzr\zebar\errors.log)' })
  }
}
$line = '[ok] live on the desktop of {0}: {1}' -f $env:USERNAME, ($done -join ', ')
Set-Content -LiteralPath (Join-Path $Here 'apply-live.log') -Value ('{0:yyyy-MM-dd HH:mm:ss} {1}' -f (Get-Date), $line) -Encoding UTF8
Write-Output $line
