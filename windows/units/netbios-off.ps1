# netbios-off (windows/roles/base.nix): NetBIOS over TCP/IP off on every interface, as LLMNR is
# (decisions/log.md#d152): nothing listens on 137 to 139, and no name is broadcast. Name lookup
# is DNS alone, as on Arch.
# The Script unit runs this text as its script block, with -Mode Get, Test (exactly one bool)
# or Set. Windows PowerShell 5.1 and 7.
param([Parameter(Mandatory = $true)][ValidateSet('Get', 'Test', 'Set')][string]$Mode)

$base = 'HKLM:\SYSTEM\CurrentControlSet\Services\NetBT\Parameters\Interfaces'

function Get-DramUnit {
  @{ Result = ((Get-ChildItem $base | ForEach-Object { (Get-ItemProperty $_.PSPath).NetbiosOptions }) -join ',') }
}

function Test-DramUnit {
  foreach ($k in Get-ChildItem $base) { if ((Get-ItemProperty $k.PSPath).NetbiosOptions -ne 2) { return $false } }
  return $true
}

function Set-DramUnit {
  foreach ($k in Get-ChildItem $base) { Set-ItemProperty -Path $k.PSPath -Name NetbiosOptions -Value 2 -Type DWord }
}

switch ($Mode) {
  'Get' { Get-DramUnit }
  'Test' { Test-DramUnit }
  'Set' { Set-DramUnit }
}
