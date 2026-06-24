Set-StrictMode -Version Latest

Import-Module (Join-Path $PSScriptRoot 'Common.psm1') -Force

function Read-ZtgEnv {
  param([string]$Path = '.env')

  $resolved = Resolve-ZtgPath $Path
  if (-not (Test-Path -LiteralPath $resolved)) {
    throw "Config file not found: $resolved. Run .\scripts\windows\init-config.ps1 first."
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
    PROXY_PUBLIC_ACCESS = 'false'
    PROXY_ALLOWED_CLIENT_CIDRS = ''
    LOCAL_PROXY_PORT = '20808'
    REMOTE_PORTS = '3389'
    PROXY_MODE = 'manual'
  }

  foreach ($key in $defaults.Keys) {
    if (-not $envMap.Contains($key) -or [string]::IsNullOrWhiteSpace([string]$envMap[$key])) {
      $envMap[$key] = $defaults[$key]
    }
  }
  if (-not $envMap.Contains('PROXY_CONNECT_HOST') -or [string]::IsNullOrWhiteSpace([string]$envMap['PROXY_CONNECT_HOST'])) {
    $envMap['PROXY_CONNECT_HOST'] = $envMap['UBUNTU_ZT_IP']
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
  $publicAccessValue = ([string]$Config['PROXY_PUBLIC_ACCESS']).ToLowerInvariant()
  $publicAccess = @('true', '1', 'yes', 'y', 'on') -contains $publicAccessValue
  if ($Config['PROXY_BIND_IP'] -eq '0.0.0.0' -and -not $publicAccess) {
    throw 'PROXY_BIND_IP=0.0.0.0 is only allowed when PROXY_PUBLIC_ACCESS=true. Default private mode should use the Ubuntu ZeroTier IP.'
  }
  $hasProxyUsername = $Config.Contains('PROXY_USERNAME') -and -not [string]::IsNullOrWhiteSpace([string]$Config['PROXY_USERNAME'])
  $hasProxyPassword = $Config.Contains('PROXY_PASSWORD') -and -not [string]::IsNullOrWhiteSpace([string]$Config['PROXY_PASSWORD'])
  if ($hasProxyUsername -xor $hasProxyPassword) {
    throw 'PROXY_USERNAME and PROXY_PASSWORD must be set together, or both left empty to disable proxy authentication.'
  }
  if ($RequireProxyCredentials -and -not ($hasProxyUsername -and $hasProxyPassword)) {
    throw 'PROXY_USERNAME and PROXY_PASSWORD are required when proxy authentication is enabled.'
  }
  if ($publicAccess) {
    if ([string]::IsNullOrWhiteSpace([string]$Config['PROXY_CONNECT_HOST']) -or [string]$Config['PROXY_CONNECT_HOST'] -eq [string]$Config['UBUNTU_ZT_IP']) {
      Write-ZtgWarn 'PROXY_PUBLIC_ACCESS=true but PROXY_CONNECT_HOST is not a server public IP. Clients may still use the slower ZeroTier entry.'
    }
    if ([string]::IsNullOrWhiteSpace([string]$Config['PROXY_ALLOWED_CLIENT_CIDRS'])) {
      Write-ZtgWarn 'PROXY_PUBLIC_ACCESS=true and PROXY_ALLOWED_CLIENT_CIDRS is empty. Public proxy access will allow all source IPs unless another firewall restricts it.'
    }
    if (-not ($hasProxyUsername -and $hasProxyPassword)) {
      Write-ZtgWarn 'Proxy authentication is disabled. This is allowed, but all-source public access can be abused if exposed to the Internet.'
    }
  }
}

Export-ModuleMember -Function Read-ZtgEnv,Assert-ZtgEnv
