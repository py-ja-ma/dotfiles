# vscodium-open-remote-ssh (windows/roles/dev.nix): Open Remote - SSH in VSCodium (jeanp413,
# MIT, Open VSX; accepted 2026-10-11), not Open Remote - WSL.
# The Script unit runs this text as its script block, with -Mode Get, Test (exactly one bool)
# or Set; the three bodies are what it ran inline before it moved to its own file. Windows
# PowerShell 5.1 and 7.
param([Parameter(Mandatory = $true)][ValidateSet('Get', 'Test', 'Set')][string]$Mode)

function Get-DramUnit {
  @{ Result = "open-remote-ssh" }
}

function Test-DramUnit {
  $ErrorActionPreference = 'Continue'
  $cli = @((Join-Path $env:ProgramFiles 'VSCodium\bin\codium.cmd'), (Join-Path $env:LOCALAPPDATA 'Programs\VSCodium\bin\codium.cmd')) | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
  if (-not $cli) { return $false }
  return [bool](@(& $cli --list-extensions 2>$null) -contains 'jeanp413.open-remote-ssh')
}

function Set-DramUnit {
  # a native command's stderr is a terminating error in Windows PowerShell 5.1 under Stop
  $ErrorActionPreference = 'Continue'
  $cli = @((Join-Path $env:ProgramFiles 'VSCodium\bin\codium.cmd'), (Join-Path $env:LOCALAPPDATA 'Programs\VSCodium\bin\codium.cmd')) | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
  if (-not $cli) { throw 'VSCodium is not installed (the vscodium unit)' }
  & $cli --install-extension jeanp413.open-remote-ssh 2>&1 | Out-Null
  if ($LASTEXITCODE -ne 0) { throw "codium --install-extension jeanp413.open-remote-ssh failed (exit $LASTEXITCODE; Open VSX unreachable?)" }
}

switch ($Mode) {
  'Get' { Get-DramUnit }
  'Test' { Test-DramUnit }
  'Set' { Set-DramUnit }
}
