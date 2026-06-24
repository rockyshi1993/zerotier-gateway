[CmdletBinding()]
param(
  [string]$Env = '.env',
  [string]$Url = 'https://api.ipify.org',
  [switch]$Help
)

$ErrorActionPreference = 'Stop'
$lib = Join-Path $PSScriptRoot 'lib'
Import-Module (Join-Path $lib 'Common.psm1') -Force
Import-Module (Join-Path $lib 'Env.psm1') -Force

function Write-ZtgInfo { param([string]$Message) Write-Host "[INFO] $Message" }

if ($Help) {
  @'
Usage:
  .\scripts\windows\test-proxy.ps1
  .\scripts\windows\test-proxy.ps1 -Url https://example.com
'@ | Write-Host
  exit 0
}

$config = Read-ZtgEnv -Path $Env
$proxyHost = if ($config.Contains('PROXY_CONNECT_HOST') -and -not [string]::IsNullOrWhiteSpace([string]$config['PROXY_CONNECT_HOST'])) {
  [string]$config['PROXY_CONNECT_HOST']
} else {
  [string]$config['UBUNTU_ZT_IP']
}
$endpoint = "${proxyHost}:$($config['PROXY_PORT'])"
Write-ZtgInfo "Testing proxy endpoint $endpoint"
Test-NetConnection -ComputerName $proxyHost -Port ([int]$config['PROXY_PORT']) | Format-List | Out-String | Write-Host
Write-ZtgInfo "Optional exit IP test URL: $Url"
