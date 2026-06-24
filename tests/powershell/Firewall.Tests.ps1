$ErrorActionPreference = 'Stop'

$root = Resolve-Path (Join-Path $PSScriptRoot '..\..')
$firewallModule = Join-Path $root 'scripts\windows\lib\Firewall.psm1'
Import-Module (Join-Path $root 'scripts\windows\lib\Env.psm1') -Force
Import-Module $firewallModule -Force -DisableNameChecking

$config = Read-ZtgEnv -Path (Join-Path $root 'tests\fixtures\example.env')
$homePlan = @(New-ZtgFirewallPlan -Config $config -Role Home)
if ($homePlan.Count -ne 2) {
  throw 'Home firewall plan should include direct and relay rules.'
}

$homeDirectRule = $homePlan | Where-Object { $_.DisplayName -eq 'ZT Gateway Remote Inbound Home 3389' }
if (-not $homeDirectRule) {
  throw 'Home firewall plan should include a direct inbound rule.'
}
if ($homeDirectRule.RemoteAddress -ne $config['WORK_PC_ZT_IP']) {
  throw 'Home firewall plan should allow the Work ZeroTier IP.'
}

$homeRelayRule = $homePlan | Where-Object { $_.DisplayName -eq 'ZT Gateway Relay Inbound Home 3389' }
if (-not $homeRelayRule) {
  throw 'Home firewall plan should include a relay inbound rule.'
}
if ($homeRelayRule.RemoteAddress -ne $config['UBUNTU_ZT_IP']) {
  throw 'Home relay firewall plan should allow the Ubuntu ZeroTier IP.'
}

$workPlan = @(New-ZtgFirewallPlan -Config $config -Role Work)
$workRemoteAddresses = @($workPlan | ForEach-Object { $_.RemoteAddress })
if ($workRemoteAddresses -notcontains $config['HOME_PC_ZT_IP']) {
  throw 'Work firewall plan should allow the Home ZeroTier IP.'
}
if ($workRemoteAddresses -notcontains $config['UBUNTU_ZT_IP']) {
  throw 'Work relay firewall plan should allow the Ubuntu ZeroTier IP.'
}

$source = Get-Content -LiteralPath $firewallModule -Raw
if ($source -notmatch 'New-NetFirewallRule[\s\S]+-ErrorAction Stop') {
  throw 'New-NetFirewallRule must use -ErrorAction Stop.'
}
if ($source -notmatch 'Remove-NetFirewallRule -ErrorAction Stop') {
  throw 'Remove-NetFirewallRule must use -ErrorAction Stop.'
}
if ($source -notmatch 'ZT Gateway Remote Inbound \*' -or $source -notmatch 'ZT Gateway Relay Inbound \*') {
  throw 'Rollback must remove direct and relay firewall rules.'
}
if ($source -notmatch 'Assert-ZtgFirewallAdministrator') {
  throw 'Firewall changes must check for an elevated PowerShell.'
}

Write-Host 'Firewall.Tests.ps1 passed'
