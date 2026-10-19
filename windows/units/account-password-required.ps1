# account-password-required (windows/roles/base.nix): pj's account requires a password
# (decisions/log.md#d152). The flag an OEM image leaves on the first account would let a blank
# password through at sign-in and over the network.
# The Script unit runs this text as its script block, with -Mode Get, Test (exactly one bool)
# or Set. Windows PowerShell 5.1 and 7.
param([Parameter(Mandatory = $true)][ValidateSet('Get', 'Test', 'Set')][string]$Mode)

function Get-DramUnit {
  @{ Result = ('pj password required: {0}' -f (Get-LocalUser -Name pj).PasswordRequired) }
}

function Test-DramUnit {
  [bool](Get-LocalUser -Name pj).PasswordRequired
}

function Set-DramUnit {
  net.exe user pj /passwordreq:yes | Out-Null
}

switch ($Mode) {
  'Get' { Get-DramUnit }
  'Test' { Test-DramUnit }
  'Set' { Set-DramUnit }
}
