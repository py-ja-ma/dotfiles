# sounds-off (windows/roles/desktop.nix): the No Sounds scheme: every event silent (a feature
# update that adds events is caught here).
# The Script unit runs this text as its script block, with -Mode Get, Test (exactly one bool)
# or Set; the three bodies are what its document ran inline before. Windows PowerShell 5.1 and 7.
param([Parameter(Mandatory = $true)][ValidateSet('Get', 'Test', 'Set')][string]$Mode)

function Get-DramUnit {
  @{ Result = "sounds" }
}

function Test-DramUnit {
  $k = Get-Item -LiteralPath 'HKCU:\AppEvents\Schemes' -ErrorAction SilentlyContinue
  if ($null -eq $k -or [string]$k.GetValue('') -ne '.None') { return $false }
  $loud = @(Get-ChildItem -LiteralPath 'HKCU:\AppEvents\Schemes\Apps' -Recurse -ErrorAction SilentlyContinue | Where-Object { $_.PSChildName -eq '.Current' -and [string]$_.GetValue('') -ne '' })
  return ($loud.Count -eq 0)
}

function Set-DramUnit {
  if (-not (Test-Path -LiteralPath 'HKCU:\AppEvents\Schemes')) { New-Item -Path 'HKCU:\AppEvents\Schemes' -Force | Out-Null }
  Set-ItemProperty -LiteralPath 'HKCU:\AppEvents\Schemes' -Name '(default)' -Value '.None'
  Get-ChildItem -LiteralPath 'HKCU:\AppEvents\Schemes\Apps' -Recurse -ErrorAction SilentlyContinue | Where-Object { $_.PSChildName -eq '.Current' } |
    ForEach-Object { Set-ItemProperty -LiteralPath $_.PSPath -Name '(default)' -Value '' }
}

switch ($Mode) {
  'Get' { Get-DramUnit }
  'Test' { Test-DramUnit }
  'Set' { Set-DramUnit }
}
