# letterpress-wallpaper (windows/roles/desktop.nix): the Letterpress art (rEFInd's background)
# on the desktop.
# The Script unit runs this text as its script block, with -Mode Get, Test (exactly one bool)
# or Set; the three bodies are what it ran inline before it moved to its own file. Windows
# PowerShell 5.1 and 7.
param([Parameter(Mandatory = $true)][ValidateSet('Get', 'Test', 'Set')][string]$Mode)

function Get-DramUnit {
  @{ Result = (Get-ItemProperty "HKCU:\Control Panel\Desktop").Wallpaper }
}

function Test-DramUnit {
  try { (Get-ItemPropertyValue -Path "HKCU:\Control Panel\Desktop" -Name Wallpaper -ErrorAction Stop) -eq "C:\ProgramData\dram\letterpress.png" } catch { $false }
}

function Set-DramUnit {
  $k = 'HKCU:\Control Panel\Desktop'
  Set-ItemProperty -Path $k -Name Wallpaper -Value 'C:\ProgramData\dram\letterpress.png'
  Set-ItemProperty -Path $k -Name WallpaperStyle -Value '10'
  Set-ItemProperty -Path $k -Name TileWallpaper -Value '0'
}

switch ($Mode) {
  'Get' { Get-DramUnit }
  'Test' { Test-DramUnit }
  'Set' { Set-DramUnit }
}
