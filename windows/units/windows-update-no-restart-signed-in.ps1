# windows-update-no-restart-signed-in (windows/hosts/cabin-win.nix): updates download and
# install by themselves, but Windows never restarts for them while pj is signed in (option 4,
# the one that restart rule needs).
# The Script unit runs this text as its script block, with -Mode Get, Test (exactly one bool)
# or Set; the three bodies are what its document ran inline before. Windows PowerShell 5.1 and 7.
param([Parameter(Mandatory = $true)][ValidateSet('Get', 'Test', 'Set')][string]$Mode)

function Get-DramUnit {
  @{ Result = "no-restart" }
}

function Test-DramUnit {
  $k = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU'
  $v = @{ NoAutoUpdate = 0; AUOptions = 4; NoAutoRebootWithLoggedOnUsers = 1 }
  foreach ($n in $v.Keys) { try { if ((Get-ItemPropertyValue -Path $k -Name $n -ErrorAction Stop) -ne $v[$n]) { return $false } } catch { return $false } }
  return $true
}

function Set-DramUnit {
  $k = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU'
  $v = @{ NoAutoUpdate = 0; AUOptions = 4; NoAutoRebootWithLoggedOnUsers = 1 }
  if (-not (Test-Path $k)) { New-Item -Path $k -Force | Out-Null }
  foreach ($n in $v.Keys) { New-ItemProperty -Path $k -Name $n -Value $v[$n] -PropertyType DWord -Force | Out-Null }
}

switch ($Mode) {
  'Get' { Get-DramUnit }
  'Test' { Test-DramUnit }
  'Set' { Set-DramUnit }
}
