# jagex-launcher (windows/roles/gaming.nix): Jagex Launcher (waived; not in winget; its signed
# installer needs clicks, so it opens on the signed-in desktop).
# The Script unit runs this text as its script block, with -Mode Get, Test (exactly one bool)
# or Set; the three bodies are what it ran inline before it moved to its own file. Windows
# PowerShell 5.1 and 7.
param([Parameter(Mandatory = $true)][ValidateSet('Get', 'Test', 'Set')][string]$Mode)

function Get-DramUnit {
  @{ Result = (Test-Path 'C:\Program Files (x86)\Jagex Launcher\JagexLauncher.exe') }
}

function Test-DramUnit {
  Test-Path 'C:\Program Files (x86)\Jagex Launcher\JagexLauncher.exe'
}

function Set-DramUnit {
  $f = 'C:\ProgramData\dram\cache\JagexLauncherInstaller.exe'
  New-Item -ItemType Directory -Path (Split-Path $f) -Force | Out-Null
  [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
  Invoke-WebRequest -UseBasicParsing -Uri 'https://cdn.jagex.com/Jagex%20Launcher%20Installer.exe' -OutFile $f
  if ((Get-AuthenticodeSignature $f).SignerCertificate.Subject -notmatch 'O=Jagex Limited') { throw 'the Jagex installer is not signed by Jagex Limited' }
  $user = (Get-CimInstance Win32_ComputerSystem).UserName
  if (-not $user) { throw 'nobody is signed in to click through the Jagex installer' }
  $p = New-ScheduledTaskPrincipal -UserId $user -LogonType Interactive -RunLevel Highest
  Register-ScheduledTask -TaskName 'dram-open-jagex-launcher' -Action (New-ScheduledTaskAction -Execute $f) -Principal $p -Force | Out-Null
  Start-ScheduledTask -TaskName 'dram-open-jagex-launcher'
}

switch ($Mode) {
  'Get' { Get-DramUnit }
  'Test' { Test-DramUnit }
  'Set' { Set-DramUnit }
}
