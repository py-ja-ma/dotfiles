# explorer-quiet (windows/roles/desktop.nix): Explorer compact, its pane open to the current
# folder, no Gallery, no sync-provider ads; End task on the taskbar's menu (for a hung game).
# The Script unit runs this text as its script block, with -Mode Get, Test (exactly one bool)
# or Set; the three bodies are what its document ran inline before. Windows PowerShell 5.1 and 7.
param([Parameter(Mandatory = $true)][ValidateSet('Get', 'Test', 'Set')][string]$Mode)

function Get-DramUnit {
  @{ Result = "explorer" }
}

function Test-DramUnit {
  $adv = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced'
  $v = @{
    $adv = @{ UseCompactMode = 1; NavPaneExpandToCurrentFolder = 1; ShowSyncProviderNotifications = 0 }
    "$adv\TaskbarDeveloperSettings" = @{ TaskbarEndTask = 1 }
    'HKCU:\Software\Classes\CLSID\{e88865ea-0e1c-4e20-9aa6-edcd0212c87c}' = @{ 'System.IsPinnedToNameSpaceTree' = 0 }
  }
  foreach ($k in $v.Keys) { foreach ($n in $v[$k].Keys) { try { if ((Get-ItemPropertyValue -LiteralPath $k -Name $n -ErrorAction Stop) -ne $v[$k][$n]) { return $false } } catch { return $false } } }
  return $true
}

function Set-DramUnit {
  $adv = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced'
  $v = @{
    $adv = @{ UseCompactMode = 1; NavPaneExpandToCurrentFolder = 1; ShowSyncProviderNotifications = 0 }
    "$adv\TaskbarDeveloperSettings" = @{ TaskbarEndTask = 1 }
    'HKCU:\Software\Classes\CLSID\{e88865ea-0e1c-4e20-9aa6-edcd0212c87c}' = @{ 'System.IsPinnedToNameSpaceTree' = 0 }
  }
  foreach ($k in $v.Keys) {
    if (-not (Test-Path -LiteralPath $k)) { New-Item -Path $k -Force | Out-Null }
    foreach ($n in $v[$k].Keys) { New-ItemProperty -LiteralPath $k -Name $n -Value $v[$k][$n] -PropertyType DWord -Force | Out-Null }
  }
}

switch ($Mode) {
  'Get' { Get-DramUnit }
  'Test' { Test-DramUnit }
  'Set' { Set-DramUnit }
}
