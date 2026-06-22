$ErrorActionPreference = 'Stop'
$root = Resolve-Path (Join-Path $PSScriptRoot '..\..')
Import-Module (Join-Path $root 'scripts\windows\lib\Env.psm1') -Force
Import-Module (Join-Path $root 'scripts\windows\lib\ProxyRules.psm1') -Force

$config = Read-ZtgEnv -Path (Join-Path $root 'tests\fixtures\example.env')
$pac = New-ZtgPacContent -Config $config
if ($pac -notmatch '10\.246\.77\.1:10808') {
  throw 'PAC content does not include proxy endpoint.'
}
if ($pac -notmatch '"address":"10\.0\.0\.0"' -or $pac -notmatch '"mask":"255\.0\.0\.0"') {
  throw 'PAC content does not include generated CIDR netmask rules.'
}

$client = New-ZtgClientRulesContent -Config $config
if ($client -notmatch 'ubuntu-proxy') {
  throw 'Client rules do not include ubuntu-proxy outbound.'
}
if ($client -notmatch '"action":"route"') {
  throw 'Client route rules do not include explicit route action.'
}
if ($client -notmatch '"process_name":\["steam\.exe","mstsc\.exe","msrdc\.exe"\]') {
  throw 'Client process rules were not merged as an array.'
}

Write-Host 'ProxyRules.Tests.ps1 passed'
