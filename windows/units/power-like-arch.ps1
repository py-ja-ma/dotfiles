# power-like-arch (windows/hosts/cabin-win.nix): as Arch's hypridle on this desktop: never
# sleeps on AC, locks at 30 min, screens off at 45.
# The Script unit runs this text as its script block, with -Mode Get, Test (exactly one bool)
# or Set; the three bodies are what its document ran inline before. Windows PowerShell 5.1 and 7.
param([Parameter(Mandatory = $true)][ValidateSet('Get', 'Test', 'Set')][string]$Mode)

function Get-DramUnit {
  @{ Result = (powercfg.exe /getactivescheme) }
}

function Test-DramUnit {
  $ac = { param($sub, $set) foreach ($l in (powercfg.exe /query SCHEME_CURRENT $sub $set)) { if ($l -match 'Current AC Power Setting Index:\s*0x([0-9a-fA-F]+)') { return [Convert]::ToInt32($matches[1], 16) } }; return -1 }
  $lock = -1
  try { $lock = Get-ItemPropertyValue -Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System' -Name InactivityTimeoutSecs -ErrorAction Stop } catch { }
  ((& $ac SUB_SLEEP STANDBYIDLE) -eq 0) -and ((& $ac SUB_VIDEO VIDEOIDLE) -eq 2700) -and ($lock -eq 1800)
}

function Set-DramUnit {
  powercfg.exe /setactive 381b4222-f694-41f0-9685-ff5bb260df2e
  powercfg.exe /change standby-timeout-ac 0
  powercfg.exe /change monitor-timeout-ac 45
  New-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System' -Name InactivityTimeoutSecs -PropertyType DWord -Value 1800 -Force | Out-Null
}

switch ($Mode) {
  'Get' { Get-DramUnit }
  'Test' { Test-DramUnit }
  'Set' { Set-DramUnit }
}
