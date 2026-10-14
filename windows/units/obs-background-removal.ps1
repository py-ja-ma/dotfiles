# obs-background-removal (windows/roles/creator.nix): OBS background removal 1.4.1 (GPL-3.0,
# pinned by SHA-256): with OBS's own virtual camera it replaces XSplit VCam (2026-10-12).
# The Script unit runs this text as its script block, with -Mode Get, Test (exactly one bool)
# or Set; the three bodies are what it ran inline before it moved to its own file. Windows
# PowerShell 5.1 and 7.
param([Parameter(Mandatory = $true)][ValidateSet('Get', 'Test', 'Set')][string]$Mode)

function Get-DramUnit {
  @{ Result = (Test-Path 'C:\ProgramData\obs-studio\plugins\obs-backgroundremoval\dram-version.txt') }
}

function Test-DramUnit {
  $v = 'C:\ProgramData\obs-studio\plugins\obs-backgroundremoval\dram-version.txt'
  (Test-Path 'C:\ProgramData\obs-studio\plugins\obs-backgroundremoval\bin\64bit\obs-backgroundremoval.dll') -and (Test-Path $v) -and ([string](Get-Content $v -Raw)).Trim() -eq '1.4.1'
}

function Set-DramUnit {
  $url = 'https://github.com/royshil/obs-backgroundremoval/releases/download/1.4.1/obs-backgroundremoval-1.4.1-windows-x64.zip'
  $sha = '7F9C0118C348111BF384C71E23FD056FD26E999BCE90132D91DB3017C6FA1B94'
  $zip = 'C:\ProgramData\dram\cache\obs-backgroundremoval-1.4.1-windows-x64.zip'
  New-Item -ItemType Directory -Path (Split-Path $zip) -Force | Out-Null
  [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
  if (-not ((Test-Path $zip) -and (Get-FileHash $zip).Hash -eq $sha)) { Invoke-WebRequest -UseBasicParsing -Uri $url -OutFile $zip }
  if ((Get-FileHash $zip).Hash -ne $sha) { throw 'obs-backgroundremoval: the download does not match its pinned SHA-256' }
  $dst = 'C:\ProgramData\obs-studio\plugins'; $tmp = Join-Path $env:TEMP 'dram-obs-bgr'
  New-Item -ItemType Directory -Path $dst -Force | Out-Null
  if (Test-Path $tmp) { Remove-Item $tmp -Recurse -Force }
  Expand-Archive -Path $zip -DestinationPath $tmp -Force
  if (Test-Path "$dst\obs-backgroundremoval") { Remove-Item "$dst\obs-backgroundremoval" -Recurse -Force }
  Move-Item "$tmp\obs-backgroundremoval" "$dst\obs-backgroundremoval"
  Remove-Item $tmp -Recurse -Force
  Set-Content -Path "$dst\obs-backgroundremoval\dram-version.txt" -Value '1.4.1' -Encoding Ascii
}

switch ($Mode) {
  'Get' { Get-DramUnit }
  'Test' { Test-DramUnit }
  'Set' { Set-DramUnit }
}
