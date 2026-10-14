# conhost-letterpress (windows/roles/desktop.nix): the classic console (anything outside
# Windows Terminal) in the scheme's colours, from letterpress/conhost.json.
# The Script unit runs this text as its script block, with -Mode Get, Test (exactly one bool)
# or Set; the three bodies are what it ran inline before it moved to its own file. Windows
# PowerShell 5.1 and 7.
param([Parameter(Mandatory = $true)][ValidateSet('Get', 'Test', 'Set')][string]$Mode)

function Get-DramUnit {
  @{ Result = "conhost" }
}

function Test-DramUnit {
  try { $c = Get-Content -LiteralPath 'C:\ProgramData\dram\letterpress\conhost.json' -Raw -ErrorAction Stop | ConvertFrom-Json } catch { return $false }
  $ok = $true
  foreach ($pr in $c.PSObject.Properties) {
    $cur = $null
    try { $cur = Get-ItemPropertyValue -Path 'HKCU:\Console' -Name $pr.Name -ErrorAction Stop } catch { }
    # each a DWORD, compared as its 32 bits: -1 in conhost.json is read back as 4294967295
    if ($null -eq $cur -or ((([int64]$cur) -band 0xFFFFFFFFL) -ne (([int64]$pr.Value) -band 0xFFFFFFFFL))) { $ok = $false }
  }
  return $ok
}

function Set-DramUnit {
  $c = Get-Content -LiteralPath 'C:\ProgramData\dram\letterpress\conhost.json' -Raw -ErrorAction Stop | ConvertFrom-Json
  if (-not (Test-Path 'HKCU:\Console')) { New-Item -Path 'HKCU:\Console' -Force | Out-Null }
  foreach ($pr in $c.PSObject.Properties) { New-ItemProperty -Path 'HKCU:\Console' -Name $pr.Name -Value ([int]$pr.Value) -PropertyType DWord -Force | Out-Null }
}

switch ($Mode) {
  'Get' { Get-DramUnit }
  'Test' { Test-DramUnit }
  'Set' { Set-DramUnit }
}
