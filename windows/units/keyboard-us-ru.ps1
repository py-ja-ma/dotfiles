# keyboard-us-ru (windows/roles/base.nix): English (US) first, so Windows stays in English,
# then Russian; no language pack.
# The Script unit runs this text as its script block, with -Mode Get, Test (exactly one bool)
# or Set; the three bodies are what it ran inline before it moved to its own file. Windows
# PowerShell 5.1 and 7.
param([Parameter(Mandatory = $true)][ValidateSet('Get', 'Test', 'Set')][string]$Mode)

function Get-DramUnit {
  @{ Result = "keyboard" }
}

function Test-DramUnit {
  # Get-WinUserLanguageList hands back its list as ONE object, so @(...) around it made a list of one
  # ("en-US ru") and the test never held (2026-10-12): its items are enumerated; progress off too
  $code = @'
$ProgressPreference = 'SilentlyContinue'
$l = @(Get-WinUserLanguageList | ForEach-Object { $_ })
[bool](($l.Count -eq 2) -and ($l[0].LanguageTag -eq 'en-US') -and ((@($l[0].InputMethodTips) -join ',') -eq '0409:00000409') -and ($l[1].LanguageTag -match '^ru(-RU)?$') -and ((@($l[1].InputMethodTips) -join ',') -eq '0419:00000419'))
'@
  $out = & (Join-Path $env:windir 'System32\WindowsPowerShell\v1.0\powershell.exe') -NoProfile -NonInteractive -EncodedCommand ([Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($code)))
  return [bool](@($out) -contains 'True')
}

function Set-DramUnit {
  $code = @'
$ProgressPreference = 'SilentlyContinue'
$n = New-WinUserLanguageList -Language 'en-US'
$n[0].InputMethodTips.Clear(); $n[0].InputMethodTips.Add('0409:00000409')
$n.Add('ru-RU'); $n[1].InputMethodTips.Clear(); $n[1].InputMethodTips.Add('0419:00000419')
Set-WinUserLanguageList -LanguageList $n -Force
'@
  & (Join-Path $env:windir 'System32\WindowsPowerShell\v1.0\powershell.exe') -NoProfile -NonInteractive -EncodedCommand ([Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($code))) | Out-Null
  if ($LASTEXITCODE -ne 0) { throw "Set-WinUserLanguageList failed (exit $LASTEXITCODE)" }
}

switch ($Mode) {
  'Get' { Get-DramUnit }
  'Test' { Test-DramUnit }
  'Set' { Set-DramUnit }
}
