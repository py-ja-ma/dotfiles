# pointer-adwaita (windows/roles/desktop.nix): the user's Adwaita pointer scheme from those
# files, chosen (Windows Black's cursors for the four roles Adwaita has none for), and a 2 px
# text caret.
# The Script unit runs this text as its script block, with -Mode Get, Test (exactly one bool)
# or Set; the three bodies are what it ran inline before it moved to its own file. Windows
# PowerShell 5.1 and 7.
param([Parameter(Mandatory = $true)][ValidateSet('Get', 'Test', 'Set')][string]$Mode)

function Get-DramUnit {
  @{ Result = "pointer" }
}

function Test-DramUnit {
  $s = 'Adwaita'
  $raw = [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames
  $names = 'Arrow', 'Help', 'AppStarting', 'Wait', 'Crosshair', 'IBeam', 'NWPen', 'No', 'SizeNS', 'SizeWE', 'SizeNWSE', 'SizeNESW', 'SizeAll', 'UpArrow', 'Hand', 'Pin', 'Person'
  $pin = @{}
  foreach ($l in @(Get-Content -LiteralPath 'C:\ProgramData\dram\cursors\cursors.pin' -ErrorAction SilentlyContinue)) {
    $f = @(-split $l)
    if ($f.Count -ge 4 -and -not $f[0].StartsWith('#')) { $pin[$f[0]] = '%SystemRoot%\Cursors\Adwaita\' + $f[3].TrimStart('=') }
  }
  if ($pin.Count -eq 0) { return $false }
  $black = @()
  $hk = [Microsoft.Win32.Registry]::LocalMachine.OpenSubKey('SOFTWARE\Microsoft\Windows\CurrentVersion\Control Panel\Cursors\Schemes')
  if ($null -ne $hk) { $black = @(([string]$hk.GetValue('Windows Black', '', $raw)) -split ','); $hk.Close() }
  $want = @()
  for ($i = 0; $i -lt $names.Count; $i++) {
    if ($pin.ContainsKey($names[$i])) { $want += $pin[$names[$i]] } elseif ($i -lt $black.Count) { $want += $black[$i] } else { $want += '' }
  }
  $sv = ''
  $sk = [Microsoft.Win32.Registry]::CurrentUser.OpenSubKey('Control Panel\Cursors\Schemes')
  if ($null -ne $sk) { $sv = [string]$sk.GetValue($s, '', $raw); $sk.Close() }
  $ck = [Microsoft.Win32.Registry]::CurrentUser.OpenSubKey('Control Panel\Cursors')
  if ($null -eq $ck) { return $false }
  $ok = ([string]$ck.GetValue('') -eq $s) -and ([string]$ck.GetValue('Scheme Source', '') -eq '1')
  for ($i = 0; $i -lt $names.Count; $i++) { if ([string]$ck.GetValue($names[$i], '', $raw) -ne $want[$i]) { $ok = $false } }
  $ck.Close()
  $cw = $null
  try { $cw = Get-ItemPropertyValue -Path 'HKCU:\Control Panel\Desktop' -Name CaretWidth -ErrorAction Stop } catch { }
  return [bool]($ok -and ($sv -eq ($want -join ',')) -and ($cw -eq 2))
}

function Set-DramUnit {
  $s = 'Adwaita'
  $raw = [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames
  $names = 'Arrow', 'Help', 'AppStarting', 'Wait', 'Crosshair', 'IBeam', 'NWPen', 'No', 'SizeNS', 'SizeWE', 'SizeNWSE', 'SizeNESW', 'SizeAll', 'UpArrow', 'Hand', 'Pin', 'Person'
  $pin = @{}
  foreach ($l in @(Get-Content -LiteralPath 'C:\ProgramData\dram\cursors\cursors.pin' -ErrorAction Stop)) {
    $f = @(-split $l)
    if ($f.Count -ge 4 -and -not $f[0].StartsWith('#')) { $pin[$f[0]] = '%SystemRoot%\Cursors\Adwaita\' + $f[3].TrimStart('=') }
  }
  if ($pin.Count -eq 0) { throw 'no cursors listed in C:\ProgramData\dram\cursors\cursors.pin (install/windows/apply-windows.sh stages it)' }
  # the roles Adwaita has no cursor for (pen, up arrow, pin, person) keep Windows Black's, its
  # nearest dark set; an older Windows without a role leaves it empty: the system default
  $black = @()
  $hk = [Microsoft.Win32.Registry]::LocalMachine.OpenSubKey('SOFTWARE\Microsoft\Windows\CurrentVersion\Control Panel\Cursors\Schemes')
  if ($null -ne $hk) { $black = @(([string]$hk.GetValue('Windows Black', '', $raw)) -split ','); $hk.Close() }
  $want = @()
  for ($i = 0; $i -lt $names.Count; $i++) {
    if ($pin.ContainsKey($names[$i])) { $want += $pin[$names[$i]] } elseif ($i -lt $black.Count) { $want += $black[$i] } else { $want += '' }
  }
  # the scheme, so Mouse Properties lists it, then the roles themselves ("Scheme Source" 1: a
  # user scheme; apply-live.ps1's SPI_SETCURSORS shows it on a signed-in desktop at once)
  $sk = [Microsoft.Win32.Registry]::CurrentUser.CreateSubKey('Control Panel\Cursors\Schemes')
  $sk.SetValue($s, ($want -join ','), [Microsoft.Win32.RegistryValueKind]::ExpandString)
  $sk.Close()
  $ck = [Microsoft.Win32.Registry]::CurrentUser.CreateSubKey('Control Panel\Cursors')
  $ck.SetValue('', $s)
  $ck.SetValue('Scheme Source', 1, [Microsoft.Win32.RegistryValueKind]::DWord)
  for ($i = 0; $i -lt $names.Count; $i++) { $ck.SetValue($names[$i], $want[$i], [Microsoft.Win32.RegistryValueKind]::ExpandString) }
  $ck.Close()
  New-ItemProperty -Path 'HKCU:\Control Panel\Desktop' -Name CaretWidth -PropertyType DWord -Value 2 -Force | Out-Null
}

switch ($Mode) {
  'Get' { Get-DramUnit }
  'Test' { Test-DramUnit }
  'Set' { Set-DramUnit }
}
