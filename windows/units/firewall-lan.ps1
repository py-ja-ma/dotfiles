# firewall-lan (windows/roles/base.nix): the Windows Firewall as Arch's nftables on the LAN
# (decisions/log.md#d152). The Ethernet connection is Private (the home network), so sshd is
# reached through its own Private-only rule and no hand-made "ssh" rule opens port 22 on every
# profile; rules an uninstalled app left for ports or for programs that no longer exist go; and
# every profile logs what it blocks (%systemroot%\system32\LogFiles\Firewall\pfirewall.log, 16 MB).
# The Script unit runs this text as its script block, with -Mode Get, Test (exactly one bool)
# or Set. Windows PowerShell 5.1 and 7.
param([Parameter(Mandatory = $true)][ValidateSet('Get', 'Test', 'Set')][string]$Mode)

function Get-StaleRules {
  # inbound allow rules whose program is a path that is not there any more (a game or an app
  # uninstalled without its rules); the apps that are installed recreate theirs when asked
  foreach ($r in Get-NetFirewallRule -Direction Inbound -Action Allow -ErrorAction SilentlyContinue) {
    $app = ($r | Get-NetFirewallApplicationFilter).Program
    if ($app -and $app -ne 'Any' -and $app -ne 'System' -and $app -notmatch '^\\' -and -not (Test-Path -LiteralPath ([Environment]::ExpandEnvironmentVariables($app)))) { $r }
  }
}
function Get-Ethernet { Get-NetConnectionProfile -ErrorAction SilentlyContinue | Where-Object { $_.InterfaceAlias -match '^Ethernet' } | Select-Object -First 1 }
function Get-SpareSshRule {
  # a hand-made "ssh" rule beside the built-in sshd one
  $builtin = Get-NetFirewallRule -DisplayName 'OpenSSH SSH Server (sshd)' -ErrorAction SilentlyContinue | Where-Object { $_.Enabled -eq 'True' }
  if ($builtin) { Get-NetFirewallRule -DisplayName 'ssh' -ErrorAction SilentlyContinue }
}

function Get-DramUnit {
  $e = Get-Ethernet
  @{ Result = ('ethernet {0}, stale rules {1}, spare ssh rule {2}, log blocked {3}' -f $e.NetworkCategory, @(Get-StaleRules).Count, @(Get-SpareSshRule).Count, ((Get-NetFirewallProfile | ForEach-Object { $_.LogBlocked }) -join '/')) }
}

function Test-DramUnit {
  $ErrorActionPreference = 'Continue'
  $e = Get-Ethernet
  if ($e -and $e.NetworkCategory -ne 'Private') { return $false }
  if (@(Get-SpareSshRule).Count -gt 0) { return $false }
  if (@(Get-NetFirewallRule -DisplayName 'MSI Center*' -ErrorAction SilentlyContinue).Count -gt 0) { return $false }
  if (@(Get-StaleRules).Count -gt 0) { return $false }
  foreach ($p in Get-NetFirewallProfile) { if ($p.LogBlocked -ne 'True' -or $p.Enabled -ne 'True') { return $false } }
  return $true
}

function Set-DramUnit {
  $ErrorActionPreference = 'Continue'
  $e = Get-Ethernet
  if ($e -and $e.NetworkCategory -ne 'Private') { Set-NetConnectionProfile -InterfaceIndex $e.InterfaceIndex -NetworkCategory Private }
  foreach ($r in @(Get-SpareSshRule)) { Remove-NetFirewallRule -Name $r.Name }
  foreach ($r in @(Get-NetFirewallRule -DisplayName 'MSI Center*' -ErrorAction SilentlyContinue)) { Remove-NetFirewallRule -Name $r.Name }
  foreach ($r in @(Get-StaleRules)) { Remove-NetFirewallRule -Name $r.Name }
  Set-NetFirewallProfile -All -Enabled True -LogBlocked True -LogMaxSizeKilobytes 16384
}

switch ($Mode) {
  'Get' { Get-DramUnit }
  'Test' { Test-DramUnit }
  'Set' { Set-DramUnit }
}
