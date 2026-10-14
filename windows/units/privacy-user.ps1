# privacy-user (windows/roles/base.nix): no advertising ID, tailored experiences, web search,
# suggestions or silently installed apps; no online speech recognition, inking and typing data,
# typing insights, feedback prompts or app-launch tracking.
# The Script unit runs this text as its script block, with -Mode Get, Test (exactly one bool)
# or Set; the three bodies are what its document ran inline before. Windows PowerShell 5.1 and 7.
param([Parameter(Mandatory = $true)][ValidateSet('Get', 'Test', 'Set')][string]$Mode)

function Get-DramUnit {
  @{ Result = "privacy" }
}

function Test-DramUnit {
  $v = @{
    'HKCU:\Software\Microsoft\Windows\CurrentVersion\AdvertisingInfo' = @{ Enabled = 0 }
    'HKCU:\Software\Microsoft\Windows\CurrentVersion\Privacy' = @{ TailoredExperiencesWithDiagnosticDataEnabled = 0 }
    'HKCU:\Software\Policies\Microsoft\Windows\Explorer' = @{ DisableSearchBoxSuggestions = 1 }
    'HKCU:\Software\Microsoft\Windows\CurrentVersion\Search' = @{ BingSearchEnabled = 0; SearchboxTaskbarMode = 0 }
    'HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager' = @{ SilentInstalledAppsEnabled = 0; SystemPaneSuggestionsEnabled = 0; SoftLandingEnabled = 0; RotatingLockScreenEnabled = 0; RotatingLockScreenOverlayEnabled = 0; 'SubscribedContent-310093Enabled' = 0; 'SubscribedContent-338387Enabled' = 0; 'SubscribedContent-338388Enabled' = 0; 'SubscribedContent-338389Enabled' = 0; 'SubscribedContent-353694Enabled' = 0; 'SubscribedContent-353696Enabled' = 0 }
    'HKCU:\Software\Microsoft\Speech_OneCore\Settings\OnlineSpeechPrivacy' = @{ HasAccepted = 0 }
    'HKCU:\Software\Microsoft\InputPersonalization' = @{ RestrictImplicitInkCollection = 1; RestrictImplicitTextCollection = 1 }
    'HKCU:\Software\Microsoft\InputPersonalization\TrainedDataStore' = @{ HarvestContacts = 0 }
    'HKCU:\Software\Microsoft\Personalization\Settings' = @{ AcceptedPrivacyPolicy = 0 }
    'HKCU:\Software\Microsoft\Input\TIPC' = @{ Enabled = 0 }
    'HKCU:\Software\Microsoft\Input\Settings' = @{ InsightsEnabled = 0 }
    'HKCU:\Software\Microsoft\Siuf\Rules' = @{ NumberOfSIUFInPeriod = 0 }
    'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced' = @{ Start_TrackProgs = 0 }
  }
  foreach ($k in $v.Keys) { foreach ($n in $v[$k].Keys) { try { if ((Get-ItemPropertyValue -Path $k -Name $n -ErrorAction Stop) -ne $v[$k][$n]) { return $false } } catch { return $false } } }
  return $true
}

function Set-DramUnit {
  $v = @{
    'HKCU:\Software\Microsoft\Windows\CurrentVersion\AdvertisingInfo' = @{ Enabled = 0 }
    'HKCU:\Software\Microsoft\Windows\CurrentVersion\Privacy' = @{ TailoredExperiencesWithDiagnosticDataEnabled = 0 }
    'HKCU:\Software\Policies\Microsoft\Windows\Explorer' = @{ DisableSearchBoxSuggestions = 1 }
    'HKCU:\Software\Microsoft\Windows\CurrentVersion\Search' = @{ BingSearchEnabled = 0; SearchboxTaskbarMode = 0 }
    'HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager' = @{ SilentInstalledAppsEnabled = 0; SystemPaneSuggestionsEnabled = 0; SoftLandingEnabled = 0; RotatingLockScreenEnabled = 0; RotatingLockScreenOverlayEnabled = 0; 'SubscribedContent-310093Enabled' = 0; 'SubscribedContent-338387Enabled' = 0; 'SubscribedContent-338388Enabled' = 0; 'SubscribedContent-338389Enabled' = 0; 'SubscribedContent-353694Enabled' = 0; 'SubscribedContent-353696Enabled' = 0 }
    'HKCU:\Software\Microsoft\Speech_OneCore\Settings\OnlineSpeechPrivacy' = @{ HasAccepted = 0 }
    'HKCU:\Software\Microsoft\InputPersonalization' = @{ RestrictImplicitInkCollection = 1; RestrictImplicitTextCollection = 1 }
    'HKCU:\Software\Microsoft\InputPersonalization\TrainedDataStore' = @{ HarvestContacts = 0 }
    'HKCU:\Software\Microsoft\Personalization\Settings' = @{ AcceptedPrivacyPolicy = 0 }
    'HKCU:\Software\Microsoft\Input\TIPC' = @{ Enabled = 0 }
    'HKCU:\Software\Microsoft\Input\Settings' = @{ InsightsEnabled = 0 }
    'HKCU:\Software\Microsoft\Siuf\Rules' = @{ NumberOfSIUFInPeriod = 0 }
    'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced' = @{ Start_TrackProgs = 0 }
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
