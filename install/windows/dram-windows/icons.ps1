# install/windows/dram-windows/icons.ps1 - the Letterpress icons: tinted app shortcuts and folders.
#
# Dark tinted icons in the manner of macOS's Clear dark style ("Tinted Letterpress"), with dark
# Letterpress folder icons (docs/design/iconography/README.md). Windows has no icon theme for
# third-party apps, and patching its resources breaks on updates, so this re-renders
# each app's OWN icon: its glyph in vermilion shades (washi's accent, dim to pale, by the
# glyph's own light and shade) on a dark rounded tile, written as a multi-size .ico under
# C:\ProgramData\dram\icons and set on the shortcuts Windows draws from - the Start menu (all
# users' and pj's), the taskbar pins and the desktop: apps, Windows' own tools and consoles,
# Steam's .url game links; an MSI-advertised link is rewritten as a plain link to its
# program. The known folders (Desktop, Documents, Downloads,
# Music, Pictures, Videos) get their own icons tinted the same way, without a tile, through
# their desktop.ini. The Start menu keeps apps only: document, folder and web links move to
# C:\ProgramData\dram\start-tidy. Every original is kept (icons\manifest.json, a byte copy of
# each changed link in icons\originals), so -Revert puts it all back. App updates rewrite their
# shortcuts, so each converge applies it again. Store apps keep their own icons in Start; the
# system icons change through registry overrides only, never a system file
# (decisions/log.md#d135). Run as the user it themes, elevated (converge.ps1 does):
#   powershell -ExecutionPolicy Bypass -File icons.ps1 [-DryRun] [-Revert] [-Sample <exe>]
# -Sample writes one icon's 256 px PNG to icons\sample.png and changes nothing else.

param([switch]$DryRun, [switch]$Revert, [string]$Sample)
$ErrorActionPreference = 'Continue'
Add-Type -AssemblyName System.Drawing
Add-Type -TypeDefinition @'
using System; using System.Runtime.InteropServices; using System.Text;
public static class DramIcon {
  [DllImport("user32.dll", CharSet = CharSet.Unicode)]
  public static extern uint PrivateExtractIcons(string file, int index, int cx, int cy, IntPtr[] icons, uint[] ids, uint n, uint flags);
  [DllImport("user32.dll")] public static extern bool DestroyIcon(IntPtr h);
  [DllImport("shell32.dll")] public static extern void SHChangeNotify(int e, uint f, IntPtr a, IntPtr b);
  [DllImport("msi.dll", CharSet = CharSet.Unicode)]
  public static extern uint MsiGetShortcutTarget(string link, StringBuilder product, StringBuilder feature, StringBuilder component);
  [DllImport("msi.dll", CharSet = CharSet.Unicode)]
  public static extern int MsiGetComponentPath(string product, string component, StringBuilder path, ref uint len);
  [DllImport("sfc.dll", CharSet = CharSet.Unicode)] public static extern bool SfcIsFileProtected(IntPtr rpc, string path);
  [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)] public struct SHSTOCKICONINFO {
    public uint cbSize; public IntPtr hIcon; public int iSysImageIndex; public int iIcon;
    [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 260)] public string szPath; }
  [DllImport("shell32.dll", CharSet = CharSet.Unicode)] public static extern int SHGetStockIconInfo(uint siid, uint flags, ref SHSTOCKICONINFO info);
}
'@

$Dir = 'C:\ProgramData\dram\icons'
$ManifestPath = Join-Path $Dir 'manifest.json'
$Version = 'letterpress-tinted-1'   # change it to re-render every icon
# washi: the tile, its rule, and the glyph ramp from the dim accent to a pale vermilion
$TileColor = [Drawing.Color]::FromArgb(242, 0x1c, 0x14, 0x0f)
$RuleColor = [Drawing.Color]::FromArgb(46, 0xe6, 0xd6, 0xcb)
$Dark = @(0x8a, 0x31, 0x1f); $Light = @(0xd5, 0x94, 0x7f)

function Say([string]$tag, [string]$what, [string]$note) { Write-Output ('[{0}] {1}{2}' -f $tag, $what, $(if ($note) { ': ' + $note } else { '' })) }

function Get-IconBitmap([string]$loc) {
  # "path,index" (index may be a negative resource id) -> a 256 px bitmap with alpha, or $null
  $file = $loc; $idx = 0
  if ($loc -match '^(.*),\s*(-?\d+)$') { $file = $matches[1]; $idx = [int]$matches[2] }
  $file = [Environment]::ExpandEnvironmentVariables($file.Trim('"'))
  if (-not (Test-Path -LiteralPath $file)) { return $null }
  $h = New-Object IntPtr[] 1; $ids = New-Object uint32[] 1
  $n = [DramIcon]::PrivateExtractIcons($file, $idx, 256, 256, $h, $ids, 1, 0)
  if ($n -lt 1 -or $h[0] -eq [IntPtr]::Zero) { return $null }
  try { return ([Drawing.Icon]::FromHandle($h[0])).ToBitmap() } finally { [void][DramIcon]::DestroyIcon($h[0]) }
}

function New-Tinted([Drawing.Bitmap]$src, [bool]$tile) {
  # the glyph's light and shade mapped onto the ramp (one ColorMatrix), on a tile or alone
  $m = New-Object Drawing.Imaging.ColorMatrix
  $lum = 0.299, 0.587, 0.114
  for ($j = 0; $j -lt 3; $j++) {
    $d = $Dark[$j] / 255.0; $l = $Light[$j] / 255.0
    for ($i = 0; $i -lt 3; $i++) { $m[$i, $j] = [single]($lum[$i] * ($l - $d)) }
    $m[4, $j] = [single]$d
  }
  $m[3, 3] = 1; $m[4, 4] = 1
  $ia = New-Object Drawing.Imaging.ImageAttributes; $ia.SetColorMatrix($m)
  $out = New-Object Drawing.Bitmap 256, 256, ([Drawing.Imaging.PixelFormat]::Format32bppArgb)
  $g = [Drawing.Graphics]::FromImage($out)
  $g.SmoothingMode = 'AntiAlias'; $g.InterpolationMode = 'HighQualityBicubic'; $g.PixelOffsetMode = 'HighQuality'
  $g.Clear([Drawing.Color]::Transparent)
  if ($tile) {
    $r = 52; $p = New-Object Drawing.Drawing2D.GraphicsPath
    $p.AddArc(8, 8, $r, $r, 180, 90); $p.AddArc(248 - $r, 8, $r, $r, 270, 90)
    $p.AddArc(248 - $r, 248 - $r, $r, $r, 0, 90); $p.AddArc(8, 248 - $r, $r, $r, 90, 90); $p.CloseFigure()
    $g.FillPath((New-Object Drawing.SolidBrush $TileColor), $p)
    $g.DrawPath((New-Object Drawing.Pen $RuleColor, 3), $p)
    $s = 164; $o = (256 - $s) / 2
  } else { $s = 256; $o = 0 }
  $g.DrawImage($src, (New-Object Drawing.Rectangle $o, $o, $s, $s), 0, 0, $src.Width, $src.Height, 'Pixel', $ia)
  $g.Dispose()
  return $out
}

function Save-Ico([Drawing.Bitmap]$big, [string]$path) {
  # PNG-compressed entries at 256, 64, 48, 32, 24 and 16 px (Windows Vista and later read them)
  $sizes = 256, 64, 48, 32, 24, 16
  $pngs = @()
  foreach ($z in $sizes) {
    $b = New-Object Drawing.Bitmap $z, $z, ([Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $g = [Drawing.Graphics]::FromImage($b); $g.InterpolationMode = 'HighQualityBicubic'; $g.PixelOffsetMode = 'HighQuality'
    $g.DrawImage($big, 0, 0, $z, $z); $g.Dispose()
    $ms = New-Object IO.MemoryStream; $b.Save($ms, [Drawing.Imaging.ImageFormat]::Png); $pngs += , $ms.ToArray(); $b.Dispose()
  }
  $fs = [IO.File]::Create($path); $w = New-Object IO.BinaryWriter $fs
  $w.Write([uint16]0); $w.Write([uint16]1); $w.Write([uint16]$sizes.Count)
  $off = 6 + 16 * $sizes.Count
  for ($i = 0; $i -lt $sizes.Count; $i++) {
    $z = $sizes[$i]; $wz = if ($z -ge 256) { 0 } else { $z }
    $w.Write([byte]$wz); $w.Write([byte]$wz); $w.Write([byte]0); $w.Write([byte]0)
    $w.Write([uint16]1); $w.Write([uint16]32); $w.Write([uint32]$pngs[$i].Length); $w.Write([uint32]$off)
    $off += $pngs[$i].Length
  }
  foreach ($p in $pngs) { $w.Write($p) }
  $w.Close(); $fs.Close()
}

function Set-Ini([string]$ini, [string[]]$lines) {
  # desktop.ini is hidden and system: write it as Unicode with its attributes put back
  $a = (Get-Item -LiteralPath $ini -Force).Attributes
  (Get-Item -LiteralPath $ini -Force).Attributes = 'Normal'
  Set-Content -LiteralPath $ini -Value $lines -Encoding Unicode
  (Get-Item -LiteralPath $ini -Force).Attributes = $a
}

function Get-IcoFor([string]$loc, [bool]$tile, [string]$label) {
  $sha = [Security.Cryptography.SHA1]::Create()
  $key = -join ($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes("$Version|$tile|$loc".ToLowerInvariant()))[0..5] | ForEach-Object { $_.ToString('x2') })
  $safe = ($label -replace '[^A-Za-z0-9]+', '-').Trim('-').ToLowerInvariant()
  $path = Join-Path $Dir "$safe-$key.ico"
  if (Test-Path -LiteralPath $path) { return $path }
  $src = Get-IconBitmap $loc
  if (-not $src) { return $null }
  if ($DryRun) { $src.Dispose(); return $path }
  $t = New-Tinted $src $tile; Save-Ico $t $path; $t.Dispose(); $src.Dispose()
  return $path
}

function Get-StockLoc([uint32]$siid) {
  # "file,index" of one of Windows' stock shell icons (SHGetStockIconInfo, SHGSI_ICONLOCATION).
  # Once Shell Icons points the folder at our tint, the lookup returns OUR file, and tinting that
  # again would compound every run: so the first original seen is kept (stock|<siid>), and a
  # lookup into icons\ falls back to it, else to Windows' known source for the two folders
  $mk = "stock|$siid"
  $i = New-Object DramIcon+SHSTOCKICONINFO
  $i.cbSize = [Runtime.InteropServices.Marshal]::SizeOf($i)
  $loc = ''
  if ([DramIcon]::SHGetStockIconInfo($siid, 0, [ref]$i) -eq 0 -and $i.szPath) { $loc = '{0},{1}' -f $i.szPath, $i.iIcon }
  if ($loc -and $loc -notlike "$Dir*") { if (-not $DryRun) { $manifest[$mk] = $loc }; return $loc }
  if ($manifest.ContainsKey($mk)) { return $manifest[$mk] }
  $known = @{ 3 = '%SystemRoot%\System32\imageres.dll,-3'; 4 = '%SystemRoot%\System32\imageres.dll,-4' }
  if ($known.ContainsKey([int]$siid)) { return $known[[int]$siid] }
  return ''
}

function Set-RegIcon([string]$key, [string]$name, [string]$value, [string]$label) {
  # one registry icon value; its earlier state (or <absent>) and any key this made are kept in
  # the manifest, so -Revert puts the registry back as it was
  $cur = $null
  try { $cur = (Get-ItemProperty -LiteralPath $key -Name $name -ErrorAction Stop).$name } catch { }
  if ($cur -eq $value) { $n.ok++; return }
  if ($DryRun) { Say 'would' $label "$name = $value"; return }
  $mk = "reg|$key|$name"
  if (-not $manifest.ContainsKey($mk)) { $manifest[$mk] = $(if ($null -eq $cur) { '<absent>' } else { [string]$cur }) }
  $missing = @(); $k = $key
  while ($k -and -not (Test-Path -LiteralPath $k)) { $missing += $k; $k = Split-Path $k }
  foreach ($m in $missing) { if (-not $manifest.ContainsKey("regkey|$m")) { $manifest["regkey|$m"] = 1 } }
  if ($missing.Count) { New-Item -Path $key -Force | Out-Null }
  Set-ItemProperty -LiteralPath $key -Name $name -Value $value
  $n.tinted++; Say 'tinted' $label
}

function Test-Protected([string]$path) {
  # Windows Resource Protection: most of Windows' own Start-menu links under ProgramData are
  # system files (27 on cabin, 2026-10-12, Task Manager and Administrative Tools among them);
  # sfc /scannow would "repair" a tinted one. The rule: never change a system file.
  return [DramIcon]::SfcIsFileProtected([IntPtr]::Zero, $path)
}

function Save-Copy([string]$path, [string]$k) {
  # a byte copy of a shortcut before its first change (icons\originals): a link to a Store app or
  # an MSI-advertised one holds data WScript cannot show, so a broken one can be put back whole
  if ($manifest.ContainsKey("copy|$k")) { return }
  $d = Join-Path $Dir 'originals'
  New-Item -ItemType Directory -Path $d -Force | Out-Null
  $sha = [Security.Cryptography.SHA1]::Create()
  $h = -join ($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($k))[0..7] | ForEach-Object { $_.ToString('x2') })
  $to = Join-Path $d ($h + [IO.Path]::GetExtension($path))
  Copy-Item -LiteralPath $path -Destination $to -Force
  $manifest["copy|$k"] = $to
}

function Get-AdvertisedTarget([string]$path) {
  # an MSI-advertised shortcut (LinkFlags HasDarwinID, 0x1000) starts its program through the
  # installer, and WScript sees only its icon: saving it through WScript drops that data and
  # leaves a link to the icon file (Transmission, 2026-10-12). Its real program, or '' if none.
  $b = [IO.File]::ReadAllBytes($path)
  if ($b.Length -lt 0x18 -or ([BitConverter]::ToUInt32($b, 0x14) -band 0x1000) -eq 0) { return $null }
  $p = New-Object Text.StringBuilder 39; $f = New-Object Text.StringBuilder 80; $c = New-Object Text.StringBuilder 39
  if ([DramIcon]::MsiGetShortcutTarget($path, $p, $f, $c) -ne 0 -or -not $c.ToString()) { return '' }
  $len = [uint32]1024; $out = New-Object Text.StringBuilder 1024
  if ([DramIcon]::MsiGetComponentPath($p.ToString(), $c.ToString(), $out, [ref]$len) -ne 3) { return '' }   # INSTALLSTATE_LOCAL
  $exe = $out.ToString()
  if ($exe -match '\.exe$' -and (Test-Path -LiteralPath $exe)) { return $exe } else { return '' }
}

if ($Sample) {
  New-Item -ItemType Directory -Path $Dir -Force | Out-Null
  $src = Get-IconBitmap $(if ($Sample -match ',\s*-?\d+$') { $Sample } else { "$Sample,0" })
  if (-not $src) { Say 'x' $Sample 'no icon'; exit 1 }
  $t = New-Tinted $src $true; $t.Save((Join-Path $Dir 'sample.png'), [Drawing.Imaging.ImageFormat]::Png)
  $f = New-Tinted $src $false; $f.Save((Join-Path $Dir 'sample-bare.png'), [Drawing.Imaging.ImageFormat]::Png)
  Say 'ok' 'sample' "$Dir\sample.png, sample-bare.png"; exit 0
}

New-Item -ItemType Directory -Path $Dir -Force | Out-Null
$manifest = @{}
if (Test-Path $ManifestPath) { (Get-Content $ManifestPath -Raw | ConvertFrom-Json).PSObject.Properties | ForEach-Object { $manifest[$_.Name] = $_.Value } }
$shell = New-Object -ComObject WScript.Shell
$n = @{ tinted = 0; ok = 0; skip = 0; reverted = 0; tidied = 0; protected = 0 }

# --- the Start menu holds apps: document, folder and web links move out -------------------------
# Installers add manuals, sample folders and websites (OpenVPN, VLC, calibre, Steam's support
# page), and an update adds them back, so every run moves them again: to
# C:\ProgramData\dram\start-tidy\<common|user>\<same path>. -Revert puts them back.
$Tidy = 'C:\ProgramData\dram\start-tidy'
$startRoots = [ordered]@{ common = "$env:ProgramData\Microsoft\Windows\Start Menu\Programs"; user = "$env:APPDATA\Microsoft\Windows\Start Menu\Programs" }
$shellApp = New-Object -ComObject Shell.Application
function Get-LinkTarget([IO.FileInfo]$f) {
  if ($f.Extension -eq '.url') {
    $l = Select-String -LiteralPath $f.FullName -Pattern '^URL=(.*)$' | Select-Object -First 1
    if ($l) { return $l.Matches[0].Groups[1].Value } else { return '' }
  }
  $t = $shell.CreateShortcut($f.FullName).TargetPath
  if ($t) { return $t }
  try { return [string]$shellApp.Namespace($f.DirectoryName).ParseName($f.Name).GetLink.Path } catch { return '' }
}
foreach ($root in $startRoots.Keys) {
  $base = $startRoots[$root]; $kept = Join-Path $Tidy $root
  if ($Revert) {
    if (-not (Test-Path -LiteralPath $kept)) { continue }
    foreach ($f in @(Get-ChildItem -LiteralPath $kept -Recurse -File)) {
      $to = Join-Path $base $f.FullName.Substring($kept.Length).TrimStart('\')
      if (-not $DryRun) { New-Item -ItemType Directory -Path (Split-Path $to) -Force | Out-Null; Move-Item -LiteralPath $f.FullName -Destination $to -Force }
      $n.reverted++; Say 'reverted' "start: $($f.Name)"
    }
    continue
  }
  if (-not (Test-Path -LiteralPath $base)) { continue }
  $left = @{}
  foreach ($f in @(Get-ChildItem -LiteralPath $base -Recurse -File -ErrorAction SilentlyContinue | Where-Object { $_.Extension -match '^\.(lnk|url)$' })) {
    $t = Get-LinkTarget $f
    $junk = ($t -match '^(https?|mailto):') -or ($t -match '\.(txt|html?|pdf|chm|md|rtf|log)$') -or ($t -and (Test-Path -LiteralPath $t -PathType Container))
    if (-not $junk -or (Test-Protected $f.FullName)) { continue }
    $rel = $f.FullName.Substring($base.Length).TrimStart('\')
    if ($DryRun) { Say 'would' "start: $rel" "move out ($t)"; continue }
    $to = Join-Path $kept $rel
    New-Item -ItemType Directory -Path (Split-Path $to) -Force | Out-Null
    Move-Item -LiteralPath $f.FullName -Destination $to -Force
    $left[$f.DirectoryName] = 1
    $n.tidied++; Say 'tidied' "start: $rel"
  }
  # the folders that move emptied, deepest first, up to (not including) the Start menu itself
  foreach ($d in @($left.Keys | Sort-Object { $_.Length } -Descending)) {
    while ($d -and $d.Length -gt $base.Length -and -not (Get-ChildItem -LiteralPath $d -Force -ErrorAction SilentlyContinue)) {
      Remove-Item -LiteralPath $d -Force; $d = Split-Path $d
    }
  }
}

# --- shortcuts: the Start menu (all users', pj's), the taskbar pins, the desktop ----------------
$roots = @("$env:ProgramData\Microsoft\Windows\Start Menu\Programs", "$env:APPDATA\Microsoft\Windows\Start Menu\Programs",
  "$env:APPDATA\Microsoft\Internet Explorer\Quick Launch\User Pinned\TaskBar", [Environment]::GetFolderPath('Desktop'), "$env:PUBLIC\Desktop")
foreach ($lnk in @($roots | Where-Object { Test-Path $_ } | ForEach-Object { Get-ChildItem -LiteralPath $_ -Filter *.lnk -Recurse -File -ErrorAction SilentlyContinue })) {
  $sc = $shell.CreateShortcut($lnk.FullName)
  $name = $lnk.BaseName; $k = $lnk.FullName.ToLowerInvariant()
  if ($Revert) {
    if ($manifest.ContainsKey("advertised|$k") -and $manifest.ContainsKey("copy|$k")) {
      # an advertised link became a plain one: only its original bytes bring the installer's data back
      if (-not $DryRun) { Copy-Item -LiteralPath $manifest["copy|$k"] -Destination $lnk.FullName -Force }
      $n.reverted++; Say 'reverted' $name
    } elseif ($manifest.ContainsKey($k) -and $sc.IconLocation -like "$Dir*") { if (-not $DryRun) { $sc.IconLocation = $manifest[$k]; $sc.Save() }; $n.reverted++; Say 'reverted' $name }
    continue
  }
  if (Test-Protected $lnk.FullName) { $n.protected++; continue }
  $target = $sc.TargetPath
  $cur = $sc.IconLocation
  if ($cur -like "$Dir*" -and (Test-Path -LiteralPath (($cur -split ',')[0]))) { $n.ok++; continue }
  # the icon it shows today: its own IconLocation when that names a file, else its program's
  # first icon. Windows' own tools too (consoles, Control Panel, Run), so every icon is in
  # the one theme (2026-10-12)
  $own = if ($cur -and ($cur -split ',')[0]) { $cur } else { '' }
  $orig = if ($own) { $own } elseif ($target -match '\.exe$' -and (Test-Path -LiteralPath $target)) { "$target,0" } else { '' }
  if (-not $orig) { $n.skip++; continue }
  $ico = Get-IcoFor $orig $true $name
  if (-not $ico) { $n.skip++; Say 'skip' $name "no icon in $orig"; continue }
  $adv = Get-AdvertisedTarget $lnk.FullName
  if ($adv -eq '') { $n.skip++; Say 'cannot' $name 'an advertised MSI link whose program the installer does not name'; continue }
  if ($DryRun) { Say 'would' $name $(if ($adv) { "tint from $orig, as a plain link to $adv" } else { "tint from $orig" }); continue }
  Save-Copy $lnk.FullName $k
  try {
    if ($adv) {
      # a fresh plain link to the same program, written beside it and moved over it
      $tmp = Join-Path $Dir 'new.lnk'
      if (Test-Path -LiteralPath $tmp) { Remove-Item -LiteralPath $tmp -Force }
      $ns = $shell.CreateShortcut($tmp)
      $ns.TargetPath = $adv; $ns.WorkingDirectory = (Split-Path $adv); $ns.Arguments = $sc.Arguments; $ns.Description = $sc.Description
      $ns.IconLocation = "$ico,0"; $ns.Save()
      Move-Item -LiteralPath $tmp -Destination $lnk.FullName -Force
      $manifest["advertised|$k"] = $adv
    } else { $sc.IconLocation = "$ico,0"; $sc.Save() }
  } catch { $n.skip++; Say 'cannot' $name $_.Exception.Message; continue }
  $manifest[$k] = $orig
  $n.tinted++; Say 'tinted' $name
}

# --- .url links (Steam's game links): their IconFile, tinted --------------------------------------
foreach ($u in @($roots | Where-Object { Test-Path $_ } | ForEach-Object { Get-ChildItem -LiteralPath $_ -Filter *.url -Recurse -File -ErrorAction SilentlyContinue })) {
  $k = $u.FullName.ToLowerInvariant()
  $lines = @([IO.File]::ReadAllLines($u.FullName, [Text.Encoding]::Default))
  $iF = -1; $iI = -1
  for ($x = 0; $x -lt $lines.Count; $x++) { if ($lines[$x] -match '^IconFile=') { $iF = $x } elseif ($lines[$x] -match '^IconIndex=') { $iI = $x } }
  $cur = if ($iF -ge 0) { ($lines[$iF] -split '=', 2)[1].Trim() } else { '' }
  if ($Revert) {
    if ($manifest.ContainsKey($k) -and $cur -like "$Dir*") {
      $f, $ix = $manifest[$k] -split ',(?=-?\d+$)'
      if (-not $DryRun) {
        $lines[$iF] = "IconFile=$f"
        if ($iI -ge 0) { $lines[$iI] = "IconIndex=$ix" }
        [IO.File]::WriteAllLines($u.FullName, $lines, [Text.Encoding]::Default)
      }
      $n.reverted++; Say 'reverted' $u.BaseName
    }
    continue
  }
  if (-not $cur) { $n.skip++; continue }                                       # a web link: the tidy's
  if (Test-Protected $u.FullName) { $n.protected++; continue }
  if ($cur -like "$Dir*" -and (Test-Path -LiteralPath $cur)) { $n.ok++; continue }
  $idx = if ($iI -ge 0) { ($lines[$iI] -split '=', 2)[1].Trim() } else { '0' }
  $orig = "$cur,$idx"
  $ico = Get-IcoFor $orig $true $u.BaseName
  if (-not $ico) { $n.skip++; Say 'skip' $u.BaseName "no icon in $orig"; continue }
  if ($DryRun) { Say 'would' $u.BaseName "tint from $orig"; continue }
  Save-Copy $u.FullName $k
  $lines[$iF] = "IconFile=$ico"
  if ($iI -ge 0) { $lines[$iI] = 'IconIndex=0' } else { $lines = @($lines[0..$iF]) + 'IconIndex=0' + @($lines | Select-Object -Skip ($iF + 1)) }
  [IO.File]::WriteAllLines($u.FullName, $lines, [Text.Encoding]::Default)
  $manifest[$k] = $orig
  $n.tinted++; Say 'tinted' $u.BaseName
}

# --- the known folders: their own icons, tinted, through desktop.ini ---------------------------
$folders = @{ Desktop = [Environment]::GetFolderPath('Desktop'); Documents = [Environment]::GetFolderPath('MyDocuments')
  Downloads = (Join-Path $env:USERPROFILE 'Downloads'); Music = [Environment]::GetFolderPath('MyMusic')
  Pictures = [Environment]::GetFolderPath('MyPictures'); Videos = [Environment]::GetFolderPath('MyVideos') }
foreach ($f in $folders.Keys) {
  $ini = Join-Path $folders[$f] 'desktop.ini'
  if (-not (Test-Path -LiteralPath $ini)) { $n.skip++; Say 'skip' "folder $f" 'no desktop.ini'; continue }
  $lines = @(Get-Content -LiteralPath $ini -Force)
  $i = -1; for ($x = 0; $x -lt $lines.Count; $x++) { if ($lines[$x] -match '^\s*IconResource\s*=') { $i = $x } }
  $cur = if ($i -ge 0) { ($lines[$i] -split '=', 2)[1].Trim() } else { '' }
  $k = $ini.ToLowerInvariant()
  if ($Revert) {
    if ($manifest.ContainsKey($k) -and $cur -like "$Dir*") {
      if (-not $DryRun) { $lines[$i] = 'IconResource=' + $manifest[$k]; Set-Ini $ini $lines }
      $n.reverted++; Say 'reverted' "folder $f"
    }
    continue
  }
  if ($cur -like "$Dir*" -and (Test-Path -LiteralPath (($cur -split ',')[0]))) { $n.ok++; continue }
  if (-not $cur) { $n.skip++; Say 'skip' "folder $f" 'no IconResource to tint'; continue }
  $ico = Get-IcoFor $cur $false "folder-$f"
  if (-not $ico) { $n.skip++; Say 'skip' "folder $f" "no icon in $cur"; continue }
  if ($DryRun) { Say 'would' "folder $f" "tint from $cur"; continue }
  $manifest[$k] = $cur
  $lines[$i] = "IconResource=$ico,0"
  Set-Ini $ini $lines
  $n.tinted++; Say 'tinted' "folder $f"
}

# --- system icons: Explorer's own items, the drives, the generic folder ---------------------
# Registry overrides only, never a system file: the namespace items per user under
# HKCU\...\Explorer\CLSID\{GUID}\DefaultIcon (where Windows' own "Change Icon" writes them), the
# drives under HKLM\...\Explorer\DriveIcons\<letter>, the generic folder (3 closed, 4 open) under
# HKLM\...\Explorer\Shell Icons - which Windows 11 honours at small sizes only: from Medium up it
# composes the folder itself. All bare tints, like the known folders. A new value shows fully
# after the next sign-in or an Explorer restart.
if ($Revert) {
  foreach ($mk in @($manifest.Keys | Where-Object { $_ -like 'reg|*' })) {
    $rest = $mk.Substring(4); $cut = $rest.LastIndexOf('|')
    $key = $rest.Substring(0, $cut); $name = $rest.Substring($cut + 1); $was = $manifest[$mk]
    if (-not $DryRun -and (Test-Path -LiteralPath $key)) {
      if ($was -eq '<absent>') { Remove-ItemProperty -LiteralPath $key -Name $name -ErrorAction SilentlyContinue }
      else { Set-ItemProperty -LiteralPath $key -Name $name -Value $was }
    }
    $n.reverted++; Say 'reverted' "$key [$name]"
  }
  foreach ($rk in @($manifest.Keys | Where-Object { $_ -like 'regkey|*' } | Sort-Object { $_.Length } -Descending)) {
    $key = $rk.Substring(7)
    if ($DryRun -or -not (Test-Path -LiteralPath $key)) { continue }
    $it = Get-Item -LiteralPath $key
    if (-not $it.Property -and -not (Get-ChildItem -LiteralPath $key)) { Remove-Item -LiteralPath $key }
  }
} else {
  $ns = [ordered]@{ 'This PC' = '{20D04FE0-3AEA-1069-A2D8-08002B30309D}'; 'Recycle Bin' = '{645FF040-5081-101B-9F08-00AA002F954E}'
    'Network' = '{F02C1A0D-BE21-4350-88B0-7367FC96EF3C}'; 'Control Panel' = '{5399E694-6CE5-4D6C-8FCE-1D8870FDCBA0}'
    'Libraries' = '{031E4825-7B94-4dc3-B131-E946B44C8DD5}'; "User's Files" = '{59031a47-3f72-44a7-89c5-5595fe6b30ee}'
    'Home' = '{f874310e-b6b7-47dc-bc84-b9e6b38f5903}'; 'Quick access' = '{679f85cb-0220-4080-b29b-5540cc05aab6}' }
  foreach ($nm in $ns.Keys) {
    $g = $ns[$nm]; $from = "Registry::HKEY_CLASSES_ROOT\CLSID\$g\DefaultIcon"
    if (-not (Test-Path -LiteralPath $from)) { $n.skip++; continue }
    $sp = Get-ItemProperty -LiteralPath $from
    # the Recycle Bin's (default) is Explorer's: it copies Empty or Full there as the bin changes,
    # so only those two are ours (setting (default) would show a full bin as empty)
    $vals = if ($g -eq '{645FF040-5081-101B-9F08-00AA002F954E}') { @('Empty', 'Full') } else { @('(default)') }
    foreach ($v in $vals) {
      $src = [string]$sp.$v
      if (-not $src -or $src -like "$Dir*") { continue }                      # none, or already ours
      $ico = Get-IcoFor $src $false "ns-$nm"
      if (-not $ico) { $n.skip++; Say 'skip' $nm "no icon in $src"; continue }
      Set-RegIcon "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\CLSID\$g\DefaultIcon" $v "$ico,0" "$nm $v"
    }
  }
  # the drives present now, by kind (SIID_DRIVEREMOVE 7, SIID_DRIVEFIXED 8, SIID_DRIVECD 11)
  foreach ($d in @(Get-CimInstance Win32_LogicalDisk | Where-Object { $_.DriveType -in 2, 3, 5 })) {
    $L = $d.DeviceID.TrimEnd(':')
    $src = Get-StockLoc $(switch ($d.DriveType) { 2 { 7 } 5 { 11 } default { 8 } })
    $ico = if ($src) { Get-IcoFor $src $false "drive-$($d.DriveType)" } else { $null }
    if (-not $ico) { $n.skip++; Say 'skip' "drive $L" 'no stock icon'; continue }
    Set-RegIcon "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\DriveIcons\$L\DefaultIcon" '(default)' "$ico,0" "drive ${L}:"
  }
  foreach ($s in @(@('3', 3, 'folder'), @('4', 4, 'folder-open'))) {
    $src = Get-StockLoc $s[1]
    $ico = if ($src) { Get-IcoFor $src $false $s[2] } else { $null }
    if (-not $ico) { $n.skip++; Say 'skip' $s[2] 'no stock icon'; continue }
    Set-RegIcon 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Shell Icons' $s[0] "$ico,0" "the generic $($s[2])"
  }
}

if (-not $DryRun) {
  # HKLM's DriveIcons and Shell Icons make every account's Explorer read these files: only
  # SYSTEM and Administrators may write them (ProgramData lets Users create files below it)
  & icacls.exe $Dir /inheritance:r /grant:r '*S-1-5-18:(OI)(CI)F' '*S-1-5-32-544:(OI)(CI)F' '*S-1-5-32-545:(OI)(CI)RX' | Out-Null
  ($manifest | ConvertTo-Json -Depth 3) | Set-Content -Path $ManifestPath -Encoding UTF8
  [DramIcon]::SHChangeNotify(0x08000000, 0, [IntPtr]::Zero, [IntPtr]::Zero)   # SHCNE_ASSOCCHANGED: the shell reloads icons
  # that reaches only this session; the signed-in desktop's Explorer refreshes its icon cache
  # through a one-off task with that user's token
  $user = (Get-CimInstance Win32_ComputerSystem).UserName
  if (($n.tinted + $n.reverted) -gt 0 -and $user) {
    $a = New-ScheduledTaskAction -Execute (Join-Path $env:windir 'System32\ie4uinit.exe') -Argument '-show'
    Register-ScheduledTask -TaskName 'dram-icons-refresh' -Action $a -Principal (New-ScheduledTaskPrincipal -UserId $user -LogonType Interactive) -Force | Out-Null
    Start-ScheduledTask -TaskName 'dram-icons-refresh'
  }
}
Write-Output ('== icons{0}: {1} tinted, {2} ok, {3} reverted, {4} skipped, {5} Start links tidied, {6} left alone as system files (WRP)' -f $(if ($DryRun) { ' (dry run)' } else { '' }), $n.tinted, $n.ok, $n.reverted, $n.skip, $n.tidied, $n.protected)
