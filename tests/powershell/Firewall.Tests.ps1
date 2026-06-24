$ErrorActionPreference = 'Stop'

$root = Resolve-Path (Join-Path $PSScriptRoot '..\..')
$firewallModule = Join-Path $root 'scripts\windows\lib\Firewall.psm1'
Import-Module (Join-Path $root 'scripts\windows\lib\Env.psm1') -Force
Import-Module $firewallModule -Force -DisableNameChecking

$config = Read-ZtgEnv -Path (Join-Path $root 'tests\fixtures\example.env')
$homePlan = @(New-ZtgFirewallPlan -Config $config -Role Home)
if ($homePlan.Count -eq 0) {
  throw 'Firewall plan should include at least one rule.'
}
if ($homePlan[0].RemoteAddress -ne $config['WORK_PC_ZT_IP']) {
  throw 'Home firewall plan should allow the Work ZeroTier IP.'
}
if ($homePlan[0].DisplayName -notmatch '^ZT Gateway Remote Inbound Home ') {
  throw 'Firewall rule display name is not scoped to this project.'
}

$source = Get-Content -LiteralPath $firewallModule -Raw
if ($source -notmatch 'New-NetFirewallRule[\s\S]+-ErrorAction Stop') {
  throw 'New-NetFirewallRule must use -ErrorAction Stop.'
}
if ($source -notmatch 'Remove-NetFirewallRule -ErrorAction Stop') {
  throw 'Remove-NetFirewallRule must use -ErrorAction Stop.'
}
if ($source -notmatch 'Assert-ZtgFirewallAdministrator') {
  throw 'Firewall changes must check for an elevated PowerShell.'
}

Write-Host 'Firewall.Tests.ps1 passed'
