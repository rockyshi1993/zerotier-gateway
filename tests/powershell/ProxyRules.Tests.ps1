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
if ($client -notmatch '"username":\s*"test-user"' -or $client -notmatch '"password":\s*"test-pass"') {
  throw 'Client proxy auth was not rendered when credentials are set.'
}
if ($client -notmatch '"action":"route"') {
  throw 'Client route rules do not include explicit route action.'
}
if ($client -notmatch '"process_name":\["steam\.exe","mstsc\.exe","msrdc\.exe"\]') {
  throw 'Client process rules were not merged as an array.'
}
$client | ConvertFrom-Json | Out-Null

$publicConfig = [ordered]@{}
foreach ($key in $config.Keys) {
  $publicConfig[$key] = $config[$key]
}
$publicConfig['PROXY_CONNECT_HOST'] = '203.0.113.10'
$publicPac = New-ZtgPacContent -Config $publicConfig
if ($publicPac -notmatch '203\.0\.113\.10:10808') {
  throw 'PAC content should use PROXY_CONNECT_HOST when it is set.'
}
$publicClient = New-ZtgClientRulesContent -Config $publicConfig
if ($publicClient -notmatch '"server":\s*"203\.0\.113\.10"') {
  throw 'Client rules should use PROXY_CONNECT_HOST when it is set.'
}

$noAuthConfig = [ordered]@{}
foreach ($key in $config.Keys) {
  $noAuthConfig[$key] = $config[$key]
}
$noAuthConfig['PROXY_USERNAME'] = ''
$noAuthConfig['PROXY_PASSWORD'] = ''
$noAuthClient = New-ZtgClientRulesContent -Config $noAuthConfig
if ($noAuthClient -match '"username"' -or $noAuthClient -match '"password"') {
  throw 'Client proxy auth should not be rendered by default.'
}
$noAuthClient | ConvertFrom-Json | Out-Null

$halfAuthConfig = [ordered]@{}
foreach ($key in $config.Keys) {
  $halfAuthConfig[$key] = $config[$key]
}
$halfAuthConfig['PROXY_USERNAME'] = 'test-user'
$halfAuthConfig['PROXY_PASSWORD'] = ''
try {
  New-ZtgClientRulesContent -Config $halfAuthConfig | Out-Null
  throw 'Half proxy credentials should fail validation.'
} catch {
  if ($_.Exception.Message -notmatch 'must be set together') {
    throw
  }
}

Write-Host 'ProxyRules.Tests.ps1 passed'
