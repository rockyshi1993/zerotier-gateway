Set-StrictMode -Version Latest

Import-Module (Join-Path $PSScriptRoot 'Common.psm1') -Force

function Read-ZtgEnv {
  param([string]$Path = '.env')

  $resolved = Resolve-ZtgPath $Path
  if (-not (Test-Path -LiteralPath $resolved)) {
    throw "Config file not found: $resolved. Copy config/example.env to .env in the project root, then edit it."
  }

  $envMap = [ordered]@{}
  Get-Content -LiteralPath $resolved | ForEach-Object {
    $line = $_.Trim()
    if (-not $line -or $line.StartsWith('#')) {
      return
    }
    $idx = $line.IndexOf('=')
    if ($idx -lt 1) {
      return
    }
    $key = $line.Substring(0, $idx).Trim()
    $value = $line.Substring($idx + 1).Trim()
    $envMap[$key] = $value
  }

  $defaults = @{
    ZEROTIER_SUBNET = '10.246.77.0/24'
    UBUNTU_ZT_IP = '10.246.77.1'
    HOME_PC_ZT_IP = '10.246.77.10'
    WORK_PC_ZT_IP = '10.246.77.20'
    PROXY_PORT = '10808'
    PROXY_BIND_IP = '10.246.77.1'
    LOCAL_PROXY_PORT = '20808'
    REMOTE_PORTS = '3389'
    PROXY_MODE = 'manual'
  }

  foreach ($key in $defaults.Keys) {
    if (-not $envMap.Contains($key) -or [string]::IsNullOrWhiteSpace([string]$envMap[$key])) {
      $envMap[$key] = $defaults[$key]
    }
  }

  $envMap['_CONFIG_PATH'] = $resolved
  return $envMap
}

function Assert-ZtgEnv {
  param(
    [Parameter(Mandatory)][System.Collections.IDictionary]$Config,
    [switch]$RequireProxyCredentials
  )

  if (-not ($Config['ZEROTIER_NETWORK_ID'] -match '^[0-9a-fA-F]{16}$')) {
    throw 'ZEROTIER_NETWORK_ID must be a 16-character hex value.'
  }
  if ($Config['PROXY_BIND_IP'] -eq '0.0.0.0') {
    throw 'PROXY_BIND_IP must not be 0.0.0.0. Use the Ubuntu ZeroTier IP.'
  }
  $hasProxyUsername = $Config.Contains('PROXY_USERNAME') -and -not [string]::IsNullOrWhiteSpace([string]$Config['PROXY_USERNAME'])
  $hasProxyPassword = $Config.Contains('PROXY_PASSWORD') -and -not [string]::IsNullOrWhiteSpace([string]$Config['PROXY_PASSWORD'])
  if ($hasProxyUsername -xor $hasProxyPassword) {
    throw 'PROXY_USERNAME and PROXY_PASSWORD must be set together, or both left empty to disable proxy authentication.'
  }
  if ($RequireProxyCredentials -and -not ($hasProxyUsername -and $hasProxyPassword)) {
    throw 'PROXY_USERNAME and PROXY_PASSWORD are required when proxy authentication is enabled.'
  }
}

Export-ModuleMember -Function Read-ZtgEnv,Assert-ZtgEnv
