# case-display-lhm (windows/hosts/cabin-win.nix): LibreHardwareMonitor 0.9.6's library for the
# panel (MPL-2.0; the release zip, pinned by SHA-256).
# The Script unit runs this text as its script block, with -Mode Get, Test (exactly one bool)
# or Set; the three bodies are what it ran inline before it moved to its own file. Windows
# PowerShell 5.1 and 7.
param([Parameter(Mandatory = $true)][ValidateSet('Get', 'Test', 'Set')][string]$Mode)

function Get-DramUnit {
  @{ Result = (Test-Path 'C:\ProgramData\dram\case-display\lhm\LibreHardwareMonitorLib.dll') }
}

function Test-DramUnit {
  $v = 'C:\ProgramData\dram\case-display\lhm\dram-version.txt'
  (Test-Path 'C:\ProgramData\dram\case-display\lhm\LibreHardwareMonitorLib.dll') -and (Test-Path $v) -and ([string](Get-Content $v -Raw)).Trim() -eq '0.9.6'
}

function Set-DramUnit {
  $url = 'https://github.com/LibreHardwareMonitor/LibreHardwareMonitor/releases/download/v0.9.6/LibreHardwareMonitor.zip'
  $sha = '086D9F1B5A99E643EDC2CFAAAC16051685B551E4C5AC0B32A57C58C0E529C001'
  $zip = 'C:\ProgramData\dram\cache\LibreHardwareMonitor-0.9.6.zip'
  New-Item -ItemType Directory -Path (Split-Path $zip) -Force | Out-Null
  [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
  if (-not ((Test-Path $zip) -and (Get-FileHash $zip).Hash -eq $sha)) { Invoke-WebRequest -UseBasicParsing -Uri $url -OutFile $zip }
  if ((Get-FileHash $zip).Hash -ne $sha) { throw 'LibreHardwareMonitor: the download does not match its pinned SHA-256' }
  $dst = 'C:\ProgramData\dram\case-display\lhm'
  Get-ScheduledTask -TaskName 'dram-case-display' -ErrorAction SilentlyContinue | Stop-ScheduledTask
  if (Test-Path $dst) { Remove-Item $dst -Recurse -Force }
  Expand-Archive -Path $zip -DestinationPath $dst -Force
  Set-Content -Path (Join-Path $dst 'dram-version.txt') -Value '0.9.6' -Encoding Ascii
}

switch ($Mode) {
  'Get' { Get-DramUnit }
  'Test' { Test-DramUnit }
  'Set' { Set-DramUnit }
}
