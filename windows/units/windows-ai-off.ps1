# windows-ai-off (windows/roles/base.nix): Recall removed (at the next restart) and no
# snapshots, no Click to Do, no AI in Notepad or Paint.
# The Script unit runs this text as its script block, with -Mode Get, Test (exactly one bool)
# or Set; the three bodies are what its document ran inline before. Windows PowerShell 5.1 and 7.
param([Parameter(Mandatory = $true)][ValidateSet('Get', 'Test', 'Set')][string]$Mode)

function Get-DramUnit {
  @{ Result = "windows-ai" }
}

function Test-DramUnit {
  $v = @{
    'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsAI' = @{ AllowRecallEnablement = 0; DisableAIDataAnalysis = 1; DisableClickToDo = 1 }
    'HKLM:\SOFTWARE\Policies\WindowsNotepad' = @{ DisableAIFeatures = 1 }
    'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Paint' = @{ DisableCocreator = 1; DisableGenerativeFill = 1; DisableImageCreator = 1 }
  }
  foreach ($k in $v.Keys) { foreach ($n in $v[$k].Keys) { try { if ((Get-ItemPropertyValue -Path $k -Name $n -ErrorAction Stop) -ne $v[$k][$n]) { return $false } } catch { return $false } } }
  return $true
}

function Set-DramUnit {
  $v = @{
    'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsAI' = @{ AllowRecallEnablement = 0; DisableAIDataAnalysis = 1; DisableClickToDo = 1 }
    'HKLM:\SOFTWARE\Policies\WindowsNotepad' = @{ DisableAIFeatures = 1 }
    'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Paint' = @{ DisableCocreator = 1; DisableGenerativeFill = 1; DisableImageCreator = 1 }
  }
  foreach ($k in $v.Keys) {
    if (-not (Test-Path $k)) { New-Item -Path $k -Force | Out-Null }
    foreach ($n in $v[$k].Keys) { New-ItemProperty -Path $k -Name $n -Value $v[$k][$n] -PropertyType DWord -Force | Out-Null }
  }
}

switch ($Mode) {
  'Get' { Get-DramUnit }
  'Test' { Test-DramUnit }
  'Set' { Set-DramUnit }
}
