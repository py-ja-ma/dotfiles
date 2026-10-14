# edge-policies (windows/roles/base.nix): Edge is not preloaded or left running, asks nothing
# at first run, shows no rewards, shopping, sidebar, widgets or suggestions, shares no browsing
# data and blocks the Copilot extension; Edge Update makes no desktop shortcut.
# The Script unit runs this text as its script block, with -Mode Get, Test (exactly one bool)
# or Set; the three bodies are what its document ran inline before. Windows PowerShell 5.1 and 7.
param([Parameter(Mandatory = $true)][ValidateSet('Get', 'Test', 'Set')][string]$Mode)

function Get-DramUnit {
  @{ Result = "edge" }
}

function Test-DramUnit {
  $v = @{
    'HKLM:\SOFTWARE\Policies\Microsoft\Edge' = @{ StartupBoostEnabled = 0; BackgroundModeEnabled = 0; HideFirstRunExperience = 1; ShowRecommendationsEnabled = 0; PersonalizationReportingEnabled = 0; UserFeedbackAllowed = 0; DiagnosticData = 0; EdgeShoppingAssistantEnabled = 0; ShowMicrosoftRewards = 0; MicrosoftEdgeInsiderPromotionEnabled = 0; DefaultBrowserSettingsCampaignEnabled = 0; WalletDonationEnabled = 0; EdgeCollectionsEnabled = 0; WebWidgetAllowed = 0; AlternateErrorPagesEnabled = 0; HubsSidebarEnabled = 0; ConfigureDoNotTrack = 1 }
    'HKLM:\SOFTWARE\Policies\Microsoft\Edge\ExtensionInstallBlocklist' = @{ '1' = 'ofefcgjbeghpigppfmkologfjadafddi' }
    'HKLM:\SOFTWARE\Policies\Microsoft\EdgeUpdate' = @{ CreateDesktopShortcutDefault = 0 }
  }
  foreach ($k in $v.Keys) { foreach ($n in $v[$k].Keys) { try { if ((Get-ItemPropertyValue -Path $k -Name $n -ErrorAction Stop) -ne $v[$k][$n]) { return $false } } catch { return $false } } }
  return $true
}

function Set-DramUnit {
  $v = @{
    'HKLM:\SOFTWARE\Policies\Microsoft\Edge' = @{ StartupBoostEnabled = 0; BackgroundModeEnabled = 0; HideFirstRunExperience = 1; ShowRecommendationsEnabled = 0; PersonalizationReportingEnabled = 0; UserFeedbackAllowed = 0; DiagnosticData = 0; EdgeShoppingAssistantEnabled = 0; ShowMicrosoftRewards = 0; MicrosoftEdgeInsiderPromotionEnabled = 0; DefaultBrowserSettingsCampaignEnabled = 0; WalletDonationEnabled = 0; EdgeCollectionsEnabled = 0; WebWidgetAllowed = 0; AlternateErrorPagesEnabled = 0; HubsSidebarEnabled = 0; ConfigureDoNotTrack = 1 }
    'HKLM:\SOFTWARE\Policies\Microsoft\Edge\ExtensionInstallBlocklist' = @{ '1' = 'ofefcgjbeghpigppfmkologfjadafddi' }
    'HKLM:\SOFTWARE\Policies\Microsoft\EdgeUpdate' = @{ CreateDesktopShortcutDefault = 0 }
  }
  foreach ($k in $v.Keys) {
    if (-not (Test-Path $k)) { New-Item -Path $k -Force | Out-Null }
    foreach ($n in $v[$k].Keys) { $x = $v[$k][$n]; New-ItemProperty -Path $k -Name $n -Value $x -PropertyType $(if ($x -is [string]) { 'String' } else { 'DWord' }) -Force | Out-Null }
  }
}

switch ($Mode) {
  'Get' { Get-DramUnit }
  'Test' { Test-DramUnit }
  'Set' { Set-DramUnit }
}
