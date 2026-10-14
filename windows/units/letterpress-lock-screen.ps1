# letterpress-lock-screen (windows/roles/desktop.nix): the same art on the lock screen.
# The Script unit runs this text as its script block, with -Mode Get, Test (exactly one bool)
# or Set; the three bodies are what it ran inline before it moved to its own file. Windows
# PowerShell 5.1 and 7.
param([Parameter(Mandatory = $true)][ValidateSet('Get', 'Test', 'Set')][string]$Mode)

function Get-DramUnit {
  @{ Result = "lock" }
}

function Test-DramUnit {
  try { (Get-ItemPropertyValue -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\PersonalizationCSP" -Name LockScreenImagePath -ErrorAction Stop) -eq "C:\ProgramData\dram\letterpress.png" } catch { $false }
}

function Set-DramUnit {
  $k = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\PersonalizationCSP'
  if (-not (Test-Path $k)) { New-Item -Path $k -Force | Out-Null }
  New-ItemProperty -Path $k -Name LockScreenImagePath -Value 'C:\ProgramData\dram\letterpress.png' -PropertyType String -Force | Out-Null
  New-ItemProperty -Path $k -Name LockScreenImageUrl -Value 'C:\ProgramData\dram\letterpress.png' -PropertyType String -Force | Out-Null
  New-ItemProperty -Path $k -Name LockScreenImageStatus -Value 1 -PropertyType DWord -Force | Out-Null
}

switch ($Mode) {
  'Get' { Get-DramUnit }
  'Test' { Test-DramUnit }
  'Set' { Set-DramUnit }
}
