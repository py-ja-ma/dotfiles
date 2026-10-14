# cursors-machine (windows/roles/desktop.nix): the Adwaita cursors
# (install/windows/cursors.pin, each checked against its sha256 again) in the Windows Cursors
# folder, Adwaita, with GNOME's licence NOTICE; one dropped from the pin is removed.
# The Script unit runs this text as its script block, with -Mode Get, Test (exactly one bool)
# or Set; the three bodies are what it ran inline before it moved to its own file. Windows
# PowerShell 5.1 and 7.
param([Parameter(Mandatory = $true)][ValidateSet('Get', 'Test', 'Set')][string]$Mode)

function Get-DramUnit {
  @{ Result = "cursors" }
}

function Test-DramUnit {
  $src = 'C:\ProgramData\dram\cursors'
  $dst = Join-Path $env:windir 'Cursors\Adwaita'
  $want = @{}
  foreach ($l in @(Get-Content -LiteralPath (Join-Path $src 'cursors.pin') -ErrorAction SilentlyContinue)) {
    $f = @(-split $l)
    if ($f.Count -ge 4 -and -not $f[0].StartsWith('#')) { $want[$f[3].TrimStart('=')] = $f[2] }
  }
  if ($want.Count -eq 0) { return $false }
  foreach ($n in $want.Keys) {
    $t = Join-Path $dst $n
    if (-not (Test-Path -LiteralPath $t)) { return $false }
    if ((Get-FileHash -LiteralPath $t).Hash -ne $want[$n]) { return $false }
  }
  $sn = Join-Path $src 'NOTICE'
  $tn = Join-Path $dst 'NOTICE'
  if (-not ((Test-Path -LiteralPath $sn) -and (Test-Path -LiteralPath $tn))) { return $false }
  if ((Get-FileHash -LiteralPath $tn).Hash -ne (Get-FileHash -LiteralPath $sn).Hash) { return $false }
  $extra = @(Get-ChildItem -LiteralPath $dst -File | Where-Object { $_.Name -ne 'NOTICE' -and -not $want.ContainsKey($_.Name) })
  return ($extra.Count -eq 0)
}

function Set-DramUnit {
  $src = 'C:\ProgramData\dram\cursors'
  $dst = Join-Path $env:windir 'Cursors\Adwaita'
  $want = @{}
  foreach ($l in @(Get-Content -LiteralPath (Join-Path $src 'cursors.pin') -ErrorAction Stop)) {
    $f = @(-split $l)
    if ($f.Count -ge 4 -and -not $f[0].StartsWith('#')) { $want[$f[3].TrimStart('=')] = $f[2] }
  }
  if ($want.Count -eq 0) { throw "no cursors listed in $src\cursors.pin (install/windows/apply-windows.sh stages it)" }
  # the staged copies are held to the pin again: only the pinned bytes reach the Windows folder
  foreach ($n in $want.Keys) {
    $s = Join-Path $src $n
    if (-not (Test-Path -LiteralPath $s)) { throw "$s is missing (install/windows/apply-windows.sh stages it)" }
    if ((Get-FileHash -LiteralPath $s).Hash -ne $want[$n]) { throw "$s does not match its sha256 in cursors.pin - refused" }
  }
  if (-not (Test-Path -LiteralPath (Join-Path $src 'NOTICE'))) { throw "$src\NOTICE is missing (install/windows/apply-windows.sh writes it)" }
  if (-not (Test-Path -LiteralPath $dst)) { New-Item -ItemType Directory -Path $dst -Force | Out-Null }
  foreach ($n in @($want.Keys) + @('NOTICE')) {
    $s = Join-Path $src $n
    $t = Join-Path $dst $n
    if (-not ((Test-Path -LiteralPath $t) -and ((Get-FileHash -LiteralPath $t).Hash -eq (Get-FileHash -LiteralPath $s).Hash))) { Copy-Item -LiteralPath $s -Destination $t -Force -ErrorAction Stop }
  }
  # a cursor that left the pin leaves the folder too
  Get-ChildItem -LiteralPath $dst -File | Where-Object { $_.Name -ne 'NOTICE' -and -not $want.ContainsKey($_.Name) } | Remove-Item -Force -ErrorAction Stop
}

switch ($Mode) {
  'Get' { Get-DramUnit }
  'Test' { Test-DramUnit }
  'Set' { Set-DramUnit }
}
