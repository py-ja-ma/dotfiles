# fonts-machine (windows/roles/desktop.nix): the house fonts for every account (Windows Fonts
# folder + HKLM), pinned by install/windows/fonts.pin; one removed from the pin is removed
# here.
# The Script unit runs this text as its script block, with -Mode Get, Test (exactly one bool)
# or Set; the three bodies are what it ran inline before it moved to its own file. Windows
# PowerShell 5.1 and 7.
param([Parameter(Mandatory = $true)][ValidateSet('Get', 'Test', 'Set')][string]$Mode)

function Get-DramUnit {
  @{ Result = "fonts" }
}

function Test-DramUnit {
  $src = 'C:\ProgramData\dram\fonts'
  $dst = Join-Path $env:windir 'Fonts'
  $reg = Get-Item -LiteralPath 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Fonts'
  $have = @(Get-ChildItem -LiteralPath $src -File -ErrorAction SilentlyContinue | Where-Object { $_.Extension -match '^\.(otf|ttf)$' })
  if ($have.Count -eq 0) { return $false }
  foreach ($f in $have) {
    $t = Join-Path $dst $f.Name
    if (-not (Test-Path -LiteralPath $t)) { return $false }
    if ((Get-FileHash -LiteralPath $t).Hash -ne (Get-FileHash -LiteralPath $f.FullName).Hash) { return $false }
    $kind = if ($f.Extension -eq '.otf') { 'OpenType' } else { 'TrueType' }
    if ([string]$reg.GetValue("$($f.BaseName) ($kind)") -ne $f.Name) { return $false }
  }
  $list = 'C:\ProgramData\dram\fonts.installed'
  if (Test-Path -LiteralPath $list) {
    $names = @($have | ForEach-Object { $_.Name })
    foreach ($n in @(Get-Content -LiteralPath $list)) {
      if ($n -and ($names -notcontains $n) -and (Test-Path -LiteralPath (Join-Path $dst $n))) { return $false }
    }
  }
  return $true
}

function Set-DramUnit {
  $src = 'C:\ProgramData\dram\fonts'
  $dst = Join-Path $env:windir 'Fonts'
  $key = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Fonts'
  $list = 'C:\ProgramData\dram\fonts.installed'
  $have = @(Get-ChildItem -LiteralPath $src -File -ErrorAction SilentlyContinue | Where-Object { $_.Extension -match '^\.(otf|ttf)$' })
  if ($have.Count -eq 0) { throw "no fonts in $src (install/windows/apply-windows.sh stages them from fonts.pin)" }
  $busy = @()
  foreach ($f in $have) {
    $t = Join-Path $dst $f.Name
    if (-not ((Test-Path -LiteralPath $t) -and ((Get-FileHash -LiteralPath $t).Hash -eq (Get-FileHash -LiteralPath $f.FullName).Hash))) {
      try { Copy-Item -LiteralPath $f.FullName -Destination $t -Force -ErrorAction Stop } catch { $busy += $f.Name; continue }
    }
    $kind = if ($f.Extension -eq '.otf') { 'OpenType' } else { 'TrueType' }
    New-ItemProperty -Path $key -Name "$($f.BaseName) ($kind)" -Value $f.Name -PropertyType String -Force | Out-Null
  }
  # a font that left fonts.pin: its registry value and file go (a loaded file at the next run after a sign-out)
  $names = @($have | ForEach-Object { $_.Name })
  $keep = @()
  if (Test-Path -LiteralPath $list) {
    foreach ($n in @(Get-Content -LiteralPath $list)) {
      if (-not $n -or ($names -contains $n)) { continue }
      $r = Get-Item -LiteralPath $key
      foreach ($v in $r.GetValueNames()) { if ([string]$r.GetValue($v) -eq $n) { Remove-ItemProperty -LiteralPath $key -Name $v -ErrorAction SilentlyContinue } }
      $t = Join-Path $dst $n
      if (Test-Path -LiteralPath $t) { Remove-Item -LiteralPath $t -Force -ErrorAction SilentlyContinue }
      if (Test-Path -LiteralPath $t) { $keep += $n }
    }
  }
  Set-Content -LiteralPath $list -Value (@($names) + @($keep)) -Encoding ASCII
  if ($busy.Count -gt 0) { throw "$($busy -join ', '): an older copy is loaded - sign out of Windows, then converge again" }
}

switch ($Mode) {
  'Get' { Get-DramUnit }
  'Test' { Test-DramUnit }
  'Set' { Set-DramUnit }
}
