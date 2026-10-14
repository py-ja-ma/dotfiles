# case-display-task (windows/hosts/cabin-win.nix): the SYSTEM task dram-case-display:
# case-display.ps1 from startup, restarted if it stops.
# The Script unit runs this text as its script block, with -Mode Get, Test (exactly one bool)
# or Set; the three bodies are what it ran inline before it moved to its own file. Windows
# PowerShell 5.1 and 7.
param([Parameter(Mandatory = $true)][ValidateSet('Get', 'Test', 'Set')][string]$Mode)

function Get-DramUnit {
  @{ Result = "case-display" }
}

function Test-DramUnit {
  $t = $null
  try { $t = Get-ScheduledTask -TaskName 'dram-case-display' -ErrorAction Stop } catch { }
  ($null -ne $t) -and ($t.State -ne 'Disabled') -and ([string](@($t.Actions)[0].Arguments) -match 'case-display\.ps1')
}

function Set-DramUnit {
  $a = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument '-NoProfile -NonInteractive -ExecutionPolicy Bypass -WindowStyle Hidden -File C:\ProgramData\dram\case-display.ps1'
  $p = New-ScheduledTaskPrincipal -UserId 'SYSTEM' -LogonType ServiceAccount -RunLevel Highest
  $st = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -ExecutionTimeLimit ([TimeSpan]::Zero) -RestartCount 999 -RestartInterval (New-TimeSpan -Minutes 1) -MultipleInstances IgnoreNew
  Register-ScheduledTask -TaskName 'dram-case-display' -Action $a -Principal $p -Settings $st -Trigger (New-ScheduledTaskTrigger -AtStartup) -Force | Out-Null
  Start-ScheduledTask -TaskName 'dram-case-display'
}

switch ($Mode) {
  'Get' { Get-DramUnit }
  'Test' { Test-DramUnit }
  'Set' { Set-DramUnit }
}
