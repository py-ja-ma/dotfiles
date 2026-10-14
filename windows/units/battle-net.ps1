# battle-net (windows/roles/gaming.nix): Battle.net (its package needs an install location,
# which WinGetPackage cannot pass).
# The Script unit runs this text as its script block, with -Mode Get, Test (exactly one bool)
# or Set; the three bodies are what it ran inline before it moved to its own file. Windows
# PowerShell 5.1 and 7.
param([Parameter(Mandatory = $true)][ValidateSet('Get', 'Test', 'Set')][string]$Mode)

function Get-DramUnit {
  @{ Result = (Test-Path 'C:\Program Files (x86)\Battle.net\Battle.net.exe') }
}

function Test-DramUnit {
  Test-Path 'C:\Program Files (x86)\Battle.net\Battle.net.exe'
}

function Set-DramUnit {
  $w = Join-Path $env:LOCALAPPDATA 'Microsoft\WindowsApps\winget.exe'
  & $w install --id Blizzard.BattleNet --exact --source winget --location 'C:\Program Files (x86)\Battle.net' --accept-source-agreements --accept-package-agreements --disable-interactivity | Out-Null
}

switch ($Mode) {
  'Get' { Get-DramUnit }
  'Test' { Test-DramUnit }
  'Set' { Set-DramUnit }
}
