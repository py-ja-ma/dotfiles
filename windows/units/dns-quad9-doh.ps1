# SPDX-FileCopyrightText: 2026 Patrick Jordan
# SPDX-License-Identifier: MIT
#
# dns-quad9-doh (windows/hosts/cabin-win.nix): Quad9 (9.9.9.9, 149.112.112.112 and IPv6) over
# DNS-over-HTTPS on the Ethernet adapter, plaintext fallback allowed.
# The Script unit runs this text as its script block, with -Mode Get, Test (exactly one bool)
# or Set; the three bodies are what it ran inline before it moved to its own file. Windows
# PowerShell 5.1 and 7.
# Alone, elevated: powershell -File dns-quad9-doh.ps1 -Mode Test, then -Mode Set
# See: docs/security/network/dns.md
param([Parameter(Mandatory = $true)][ValidateSet('Get', 'Test', 'Set')][string]$Mode)

function Get-DramUnit {
  @{ Result = "dns" }
}

function Test-DramUnit {
  $q4 = @('9.9.9.9', '149.112.112.112')
  $q6 = @('2620:fe::fe', '2620:fe::fe:9')
  $nics = @(Get-NetAdapter -Physical -ErrorAction SilentlyContinue | Where-Object { $_.PhysicalMediaType -eq '802.3' })
  if ($nics.Count -eq 0) { return $false }
  foreach ($a in @($q4 + $q6)) {
    $d = $null
    try { $d = Get-DnsClientDohServerAddress -ServerAddress $a -ErrorAction Stop } catch { return $false }
    if ($null -eq $d) { return $false }
    if (-not ($d.AutoUpgrade -and $d.AllowFallbackToUdp -and ([string]$d.DohTemplate -eq 'https://dns.quad9.net/dns-query'))) { return $false }
  }
  foreach ($n in $nics) {
    $v4 = @(Get-DnsClientServerAddress -InterfaceIndex $n.ifIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue | ForEach-Object { $_.ServerAddresses })
    if (($v4 -join ',') -ne ($q4 -join ',')) { return $false }
    $s6 = @(Get-DnsClientServerAddress -InterfaceIndex $n.ifIndex -AddressFamily IPv6 -ErrorAction SilentlyContinue)
    if ($s6.Count -gt 0) {
      $v6 = @($s6 | ForEach-Object { $_.ServerAddresses })
      if (($v6 -join ',') -ne ($q6 -join ',')) { return $false }
    }
  }
  return $true
}

function Set-DramUnit {
  $q4 = @('9.9.9.9', '149.112.112.112')
  $q6 = @('2620:fe::fe', '2620:fe::fe:9')
  $t = 'https://dns.quad9.net/dns-query'
  # the encryption first: each address upgrades to DoH, falling back to plain DNS if DoH fails
  foreach ($a in @($q4 + $q6)) {
    if (Get-DnsClientDohServerAddress -ServerAddress $a -ErrorAction SilentlyContinue) {
      Set-DnsClientDohServerAddress -ServerAddress $a -DohTemplate $t -AutoUpgrade $true -AllowFallbackToUdp $true -ErrorAction Stop | Out-Null
    } else {
      Add-DnsClientDohServerAddress -ServerAddress $a -DohTemplate $t -AutoUpgrade $true -AllowFallbackToUdp $true -ErrorAction Stop | Out-Null
    }
  }
  $nics = @(Get-NetAdapter -Physical -ErrorAction SilentlyContinue | Where-Object { $_.PhysicalMediaType -eq '802.3' })
  if ($nics.Count -eq 0) { throw 'no Ethernet adapter found: Quad9 goes on the wired one only' }
  foreach ($n in $nics) {
    # an adapter without IPv6 bound takes the IPv4 pair alone
    $s6 = @(Get-DnsClientServerAddress -InterfaceIndex $n.ifIndex -AddressFamily IPv6 -ErrorAction SilentlyContinue)
    $all = @($q4) + @(if ($s6.Count -gt 0) { $q6 })
    Set-DnsClientServerAddress -InterfaceIndex $n.ifIndex -ServerAddresses $all -ErrorAction Stop
  }
  Clear-DnsClientCache
}

switch ($Mode) {
  'Get' { Get-DramUnit }
  'Test' { Test-DramUnit }
  'Set' { Set-DramUnit }
}
