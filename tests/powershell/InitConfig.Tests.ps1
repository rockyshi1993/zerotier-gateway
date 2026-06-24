$ErrorActionPreference = 'Stop'

$root = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$tmp = [System.IO.Path]::GetTempFileName()
$tmpPublic = [System.IO.Path]::GetTempFileName()

try {
  "0123456789abcdef`n`n`n`n`n`nn`nn`n" |
    powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $root 'scripts\windows\init-config.ps1') -Env $tmp |
    Out-Null

  $content = Get-Content -LiteralPath $tmp
  if (-not ($content -contains 'ZEROTIER_NETWORK_ID=0123456789abcdef')) {
    throw 'Init config did not write ZEROTIER_NETWORK_ID.'
  }
  if (-not ($content -contains 'UBUNTU_ZT_IP=10.246.77.1')) {
    throw 'Init config did not keep the default Ubuntu IP.'
  }
  if (-not ($content -contains 'PROXY_USERNAME=')) {
    throw 'Init config should disable proxy auth by default.'
  }
  if (-not ($content -contains 'PROXY_PUBLIC_ACCESS=false')) {
    throw 'Init config should keep public proxy access disabled by default.'
  }
  if (-not ($content -contains 'PROXY_CONNECT_HOST=10.246.77.1')) {
    throw 'Init config should use the Ubuntu ZeroTier IP as the default client proxy host.'
  }

  "fedcba9876543210`n10.99.0.0/24`n10.99.0.1`n10.99.0.10`n10.99.0.20`n18080`ny`n0.0.0.0`n203.0.113.10`n198.51.100.23/32`nn`n" |
    powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $root 'scripts\windows\init-config.ps1') -Env $tmpPublic |
    Out-Null

  $publicContent = Get-Content -LiteralPath $tmpPublic
  if (-not ($publicContent -contains 'PROXY_PUBLIC_ACCESS=true')) {
    throw 'Init config should enable public proxy access when requested.'
  }
  if (-not ($publicContent -contains 'PROXY_BIND_IP=0.0.0.0')) {
    throw 'Init config should bind the proxy to all interfaces for public access.'
  }
  if (-not ($publicContent -contains 'PROXY_CONNECT_HOST=203.0.113.10')) {
    throw 'Init config should write the public client proxy host.'
  }
  if (-not ($publicContent -contains 'PROXY_ALLOWED_CLIENT_CIDRS=198.51.100.23/32')) {
    throw 'Init config should write the public proxy allowlist.'
  }
  if (-not ($publicContent -contains 'PROXY_USERNAME=')) {
    throw 'Init config should keep proxy auth optional for public access.'
  }
} finally {
  Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue
  Remove-Item -LiteralPath $tmpPublic -Force -ErrorAction SilentlyContinue
}

Write-Host 'InitConfig.Tests.ps1 passed'
