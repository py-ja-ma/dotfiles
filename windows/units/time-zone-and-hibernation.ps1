# time-zone-and-hibernation (windows/hosts/cabin-win.nix): US Eastern time like Arch
# (America/New_York), hibernation off.
# The Script unit runs this text as its script block, with -Mode Get, Test (exactly one bool)
# or Set; the three bodies are what its document ran inline before. Windows PowerShell 5.1 and 7.
param([Parameter(Mandatory = $true)][ValidateSet('Get', 'Test', 'Set')][string]$Mode)

function Get-DramUnit {
  @{ Result = (Get-TimeZone).Id }
}

function Test-DramUnit {
  (Get-TimeZone).Id -eq 'Eastern Standard Time' -and -not (Test-Path C:\hiberfil.sys)
}

function Set-DramUnit {
  Set-TimeZone -Id 'Eastern Standard Time'; powercfg.exe /hibernate off
}

switch ($Mode) {
  'Get' { Get-DramUnit }
  'Test' { Test-DramUnit }
  'Set' { Set-DramUnit }
}
