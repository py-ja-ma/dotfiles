# windows-ai-fabric-manual (windows/roles/base.nix): the Windows AI Fabric service starts only
# when something asks for it (Manual), on builds that have it.
# The Script unit runs this text as its script block, with -Mode Get, Test (exactly one bool)
# or Set; the three bodies are what its document ran inline before. Windows PowerShell 5.1 and 7.
param([Parameter(Mandatory = $true)][ValidateSet('Get', 'Test', 'Set')][string]$Mode)

function Get-DramUnit {
  @{ Result = "WSAIFabricSvc" }
}

function Test-DramUnit {
  $s = Get-Service -Name 'WSAIFabricSvc' -ErrorAction SilentlyContinue
  return [bool](($null -eq $s) -or ([string]$s.StartType -eq 'Manual'))
}

function Set-DramUnit {
  if (Get-Service -Name 'WSAIFabricSvc' -ErrorAction SilentlyContinue) { Set-Service -Name 'WSAIFabricSvc' -StartupType Manual -ErrorAction Stop }
}

switch ($Mode) {
  'Get' { Get-DramUnit }
  'Test' { Test-DramUnit }
  'Set' { Set-DramUnit }
}
