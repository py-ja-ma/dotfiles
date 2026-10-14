# letterpress-look (windows/roles/desktop.nix): dark, matte, the accent from
# letterpress/accent.json on title bars, a quiet left taskbar and Start, extensions shown,
# mouse without acceleration.
# The Script unit runs this text as its script block, with -Mode Get, Test (exactly one bool)
# or Set; the three bodies are what it ran inline before it moved to its own file. Windows
# PowerShell 5.1 and 7.
param([Parameter(Mandatory = $true)][ValidateSet('Get', 'Test', 'Set')][string]$Mode)

function Get-DramUnit {
  @{ Result = "look" }
}

function Test-DramUnit {
  function Is($k, $n, $want) { try { (Get-ItemPropertyValue -Path $k -Name $n -ErrorAction Stop) -eq $want } catch { $false } }
  # a DWORD as its 32 bits: Windows reads DWM's AccentColor back unsigned (4281025728) where
  # accent.json holds it signed (-13941568), the same value
  function IsDw($k, $n, $want) { try { (([int64](Get-ItemPropertyValue -Path $k -Name $n -ErrorAction Stop)) -band 0xFFFFFFFFL) -eq (([int64]$want) -band 0xFFFFFFFFL) } catch { $false } }
  try { $a = Get-Content -LiteralPath 'C:\ProgramData\dram\letterpress\accent.json' -Raw -ErrorAction Stop | ConvertFrom-Json } catch { return $false }
  $pal = ''
  # the palette is one byte[] value: @(...) around it joined to the text "System.Byte[]", so this
  # test never held (2026-10-12); the bytes themselves are joined
  try { $pal = ([byte[]](Get-ItemPropertyValue -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Accent' -Name AccentPalette -ErrorAction Stop)) -join ',' } catch { }
  $p = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize'
  $adv = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced'
  return [bool]((Is $p SystemUsesLightTheme $a.SystemUsesLightTheme) -and (Is $p AppsUseLightTheme $a.AppsUseLightTheme) -and
    (IsDw 'HKCU:\Software\Microsoft\Windows\DWM' AccentColor $a.AccentColor) -and ($pal -eq (@($a.AccentPalette) -join ',')) -and
    (Is $adv TaskbarAl 0) -and (Is $adv Start_IrisRecommendations 0) -and (Is 'HKCU:\Control Panel\Mouse' MouseSpeed '0'))
}

function Set-DramUnit {
  $a = Get-Content -LiteralPath 'C:\ProgramData\dram\letterpress\accent.json' -Raw -ErrorAction Stop | ConvertFrom-Json
  function Set-Dw($k, $n, $v) { if (-not (Test-Path $k)) { New-Item -Path $k -Force | Out-Null }; New-ItemProperty -Path $k -Name $n -Value ([int]$v) -PropertyType DWord -Force | Out-Null }
  $p = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize'
  Set-Dw $p AppsUseLightTheme $a.AppsUseLightTheme; Set-Dw $p SystemUsesLightTheme $a.SystemUsesLightTheme; Set-Dw $p EnableTransparency 0; Set-Dw $p ColorPrevalence 0
  # the theme's accent (bin/gen-windows-look.py): DWM keeps ABGR; the palette runs light to dark, the paper last
  $d = 'HKCU:\Software\Microsoft\Windows\DWM'
  Set-Dw $d AccentColor $a.AccentColor; Set-Dw $d ColorizationColor $a.ColorizationColor; Set-Dw $d ColorizationAfterglow $a.ColorizationAfterglow; Set-Dw $d ColorPrevalence 1
  $x = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Accent'
  Set-Dw $x AccentColorMenu $a.AccentColorMenu; Set-Dw $x StartColorMenu $a.StartColorMenu
  New-ItemProperty -Path $x -Name AccentPalette -PropertyType Binary -Force -Value ([byte[]]@($a.AccentPalette)) | Out-Null
  Set-ItemProperty -Path 'HKCU:\Control Panel\Desktop' -Name AutoColorization -Value '0'
  $adv = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced'
  Set-Dw $adv TaskbarAl 0; Set-Dw $adv ShowTaskViewButton 0; Set-Dw $adv ShowCopilotButton 0
  Set-Dw $adv Start_IrisRecommendations 0; Set-Dw $adv Start_TrackDocs 0; Set-Dw $adv Start_AccountNotifications 0
  Set-Dw $adv HideFileExt 0; Set-Dw $adv LaunchTo 1
  # games: no pointer acceleration ("Enhance pointer precision" off)
  $m = 'HKCU:\Control Panel\Mouse'
  Set-ItemProperty -Path $m -Name MouseSpeed -Value '0'; Set-ItemProperty -Path $m -Name MouseThreshold1 -Value '0'; Set-ItemProperty -Path $m -Name MouseThreshold2 -Value '0'
}

switch ($Mode) {
  'Get' { Get-DramUnit }
  'Test' { Test-DramUnit }
  'Set' { Set-DramUnit }
}
