# windows-update-active-hours (windows/hosts/cabin-win.nix): active hours 08:00 to 02:00 (18
# hours, the most Windows allows): no update restart inside them.
# The Script unit runs this text as its script block, with -Mode Get, Test (exactly one bool)
# or Set; the three bodies are what its document ran inline before. Windows PowerShell 5.1 and 7.
param([Parameter(Mandatory = $true)][ValidateSet('Get', 'Test', 'Set')][string]$Mode)

function Get-DramUnit {
  @{ Result = "active-hours" }
}

function Test-DramUnit {
  $k = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate'
  $v = @{ SetActiveHours = 1; ActiveHoursStart = 8; ActiveHoursEnd = 2 }
  foreach ($n in $v.Keys) { try { if ((Get-ItemPropertyValue -Path $k -Name $n -ErrorAction Stop) -ne $v[$n]) { return $false } } catch { return $false } }
  return $true
}

function Set-DramUnit {
  $k = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate'
  $v = @{ SetActiveHours = 1; ActiveHoursStart = 8; ActiveHoursEnd = 2 }
  if (-not (Test-Path $k)) { New-Item -Path $k -Force | Out-Null }
  foreach ($n in $v.Keys) { New-ItemProperty -Path $k -Name $n -Value $v[$n] -PropertyType DWord -Force | Out-Null }
}

switch ($Mode) {
  'Get' { Get-DramUnit }
  'Test' { Test-DramUnit }
  'Set' { Set-DramUnit }
}
