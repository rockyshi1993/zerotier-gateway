$ErrorActionPreference = 'Stop'

$root = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$tmp = [System.IO.Path]::GetTempFileName()

try {
  "0123456789abcdef`n`n`n`n`n`nn`n" |
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
} finally {
  Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue
}

Write-Host 'InitConfig.Tests.ps1 passed'
