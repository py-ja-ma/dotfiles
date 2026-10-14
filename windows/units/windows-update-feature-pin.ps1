# windows-update-feature-pin (windows/hosts/cabin-win.nix): Windows 11 stays on 26H2, the
# version cabin runs, until this line moves.
# The Script unit runs this text as its script block, with -Mode Get, Test (exactly one bool)
# or Set; the three bodies are what its document ran inline before. Windows PowerShell 5.1 and 7.
param([Parameter(Mandatory = $true)][ValidateSet('Get', 'Test', 'Set')][string]$Mode)

function Get-DramUnit {
  @{ Result = "feature-pin" }
}

function Test-DramUnit {
  $k = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate'
  $v = @{ TargetReleaseVersion = 1; ProductVersion = 'Windows 11'; TargetReleaseVersionInfo = '26H2' }
  foreach ($n in $v.Keys) { try { if ((Get-ItemPropertyValue -Path $k -Name $n -ErrorAction Stop) -ne $v[$n]) { return $false } } catch { return $false } }
  return $true
}

function Set-DramUnit {
  $k = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate'
  $v = @{ TargetReleaseVersion = 1; ProductVersion = 'Windows 11'; TargetReleaseVersionInfo = '26H2' }
  if (-not (Test-Path $k)) { New-Item -Path $k -Force | Out-Null }
  foreach ($n in $v.Keys) { New-ItemProperty -Path $k -Name $n -Value $v[$n] -PropertyType $(if ($v[$n] -is [string]) { 'String' } else { 'DWord' }) -Force | Out-Null }
}

switch ($Mode) {
  'Get' { Get-DramUnit }
  'Test' { Test-DramUnit }
  'Set' { Set-DramUnit }
}
