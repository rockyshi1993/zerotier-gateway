$ErrorActionPreference = 'Stop'

$root = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$tmp = [System.IO.Path]::GetTempFileName()

try {
  Copy-Item -LiteralPath (Join-Path $root 'tests\fixtures\example.env') -Destination $tmp -Force

  & (Join-Path $root 'scripts\windows\configure-proxy-rules.ps1') `
    -Env $tmp `
    -DirectDomains 'localhost,example.internal' `
    -DirectIpCidrs '10.246.77.0/24,192.0.2.0/24' `
    -DirectProcessGroups 'remote-tools' `
    -DirectProcessNames 'custom-remote.exe' | Out-Null

  $content = Get-Content -LiteralPath $tmp
  if (-not ($content -contains 'DIRECT_DOMAINS=localhost,example.internal')) {
    throw 'Direct domain rules were not updated.'
  }
  if (-not ($content -contains 'DIRECT_IP_CIDRS=10.246.77.0/24,192.0.2.0/24')) {
    throw 'Direct IP rules were not updated.'
  }
  if (-not ($content -contains 'DIRECT_PROCESS_GROUPS=remote-tools')) {
    throw 'Direct process group was not updated.'
  }
  if (-not ($content -contains 'DIRECT_PROCESS_NAMES=custom-remote.exe')) {
    throw 'Direct process names were not updated.'
  }
  if (-not ($content -contains 'ZEROTIER_NETWORK_ID=0123456789abcdef')) {
    throw 'Unrelated config values must be preserved.'
  }
} finally {
  Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue
}

Write-Host 'ProxyRuleConfig.Tests.ps1 passed'
