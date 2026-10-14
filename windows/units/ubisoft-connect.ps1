# ubisoft-connect (windows/roles/gaming.nix): Ubisoft Connect (accepted with an Origin flag,
# 2026-10-12): Ubisoft replaces its installer in place, so winget's pinned hash goes stale; its
# own installer, Ubisoft-signed, silent.
# The Script unit runs this text as its script block, with -Mode Get, Test (exactly one bool)
# or Set; the three bodies are what it ran inline before it moved to its own file. Windows
# PowerShell 5.1 and 7.
param([Parameter(Mandatory = $true)][ValidateSet('Get', 'Test', 'Set')][string]$Mode)

function Get-DramUnit {
  @{ Result = (Test-Path 'C:\Program Files (x86)\Ubisoft\Ubisoft Game Launcher\UbisoftConnect.exe') }
}

function Test-DramUnit {
  Test-Path 'C:\Program Files (x86)\Ubisoft\Ubisoft Game Launcher\UbisoftConnect.exe'
}

function Set-DramUnit {
  $f = 'C:\ProgramData\dram\cache\UbisoftConnectInstaller.exe'
  New-Item -ItemType Directory -Path (Split-Path $f) -Force | Out-Null
  [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
  Invoke-WebRequest -UseBasicParsing -Uri 'https://static3.cdn.ubi.com/orbit/launcher_installer/UbisoftConnectInstaller.exe' -OutFile $f
  if ((Get-AuthenticodeSignature $f).SignerCertificate.Subject -notmatch 'O=UBISOFT ENTERTAINMENT INC\.') { throw 'the Ubisoft Connect installer is not signed by Ubisoft' }
  $p = Start-Process -FilePath $f -ArgumentList '/S' -PassThru
  if (-not $p.WaitForExit(900000)) { $p | Stop-Process -Force; throw 'the Ubisoft Connect installer did not finish in 15 minutes' }
  Get-Process -Name 'UbisoftConnect', 'upc' -ErrorAction SilentlyContinue | Where-Object { $_.SessionId -eq 0 } | Stop-Process -Force
}

switch ($Mode) {
  'Get' { Get-DramUnit }
  'Test' { Test-DramUnit }
  'Set' { Set-DramUnit }
}
