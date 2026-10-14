# SPDX-FileCopyrightText: 2026 Patrick Jordan
# SPDX-License-Identifier: MIT
#
# secureboot-no-revocations (windows/hosts/cabin-win.nix): Windows never queues the PCA 2011
# revocation (0x80), SVN (0x200) or SBAT (0x400) updates; Arch decides those.
# The Script unit runs this text as its script block, with -Mode Get, Test (exactly one bool)
# or Set; the three bodies are what it ran inline before it moved to its own file. Windows
# PowerShell 5.1 and 7.
# Alone, elevated: powershell -File secureboot-no-revocations.ps1 -Mode Test, then -Mode Set
# See: docs/security/boot-trust/secure-boot.md
param([Parameter(Mandatory = $true)][ValidateSet('Get', 'Test', 'Set')][string]$Mode)

function Get-DramUnit {
  @{ Result = "secureboot" }
}

function Test-DramUnit {
  $v = $null
  try { $v = Get-ItemPropertyValue -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\Secureboot' -Name AvailableUpdates -ErrorAction Stop } catch { }
  ($null -eq $v) -or ((([int]$v) -band 0x680) -eq 0)
}

function Set-DramUnit {
  $k = 'HKLM:\SYSTEM\CurrentControlSet\Control\Secureboot'
  $v = [int](Get-ItemPropertyValue -Path $k -Name AvailableUpdates)
  Set-ItemProperty -Path $k -Name AvailableUpdates -Value ($v -band (-bnot 0x680))
}

switch ($Mode) {
  'Get' { Get-DramUnit }
  'Test' { Test-DramUnit }
  'Set' { Set-DramUnit }
}
