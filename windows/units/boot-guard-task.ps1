# boot-guard-task (windows/hosts/cabin-win.nix): rEFInd first and Windows Boot Manager last in
# the firmware order at every Windows start (dram-windows/boot-guard.ps1).
# The Script unit runs this text as its script block, with -Mode Get, Test (exactly one bool)
# or Set; the three bodies are what its document ran inline before. Windows PowerShell 5.1 and 7.
param([Parameter(Mandatory = $true)][ValidateSet('Get', 'Test', 'Set')][string]$Mode)

function Get-DramUnit {
  @{ Result = "boot-guard" }
}

function Test-DramUnit {
  $t = $null
  try { $t = Get-ScheduledTask -TaskPath '\dram\' -TaskName 'boot-guard' -ErrorAction Stop } catch { }
  ($null -ne $t) -and ($t.State -ne 'Disabled') -and ([string](@($t.Actions)[0].Arguments) -match 'boot-guard\.ps1')
}

function Set-DramUnit {
  $a = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument '-NoProfile -NonInteractive -ExecutionPolicy Bypass -File C:\ProgramData\dram\boot-guard.ps1'
  $p = New-ScheduledTaskPrincipal -UserId 'SYSTEM' -LogonType ServiceAccount -RunLevel Highest
  Register-ScheduledTask -TaskPath '\dram\' -TaskName 'boot-guard' -Action $a -Principal $p -Trigger (New-ScheduledTaskTrigger -AtStartup) -Force | Out-Null
  Start-ScheduledTask -TaskPath '\dram\' -TaskName 'boot-guard'
}

switch ($Mode) {
  'Get' { Get-DramUnit }
  'Test' { Test-DramUnit }
  'Set' { Set-DramUnit }
}
