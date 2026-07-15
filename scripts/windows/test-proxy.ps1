[CmdletBinding()]
param(
  [string]$Env = '.env',
  [string]$Url = 'https://api.ipify.org',
  [switch]$SkipExitCheck,
  [switch]$Help
)

$ErrorActionPreference = 'Stop'
$lib = Join-Path $PSScriptRoot 'lib'
Import-Module (Join-Path $lib 'Common.psm1') -Force
Import-Module (Join-Path $lib 'Env.psm1') -Force

function Write-ZtgInfo { param([string]$Message) Write-Host "[INFO] $Message" }
function Write-ZtgWarn { param([string]$Message) Write-Warning $Message }

if ($Help) {
  @'
Usage:
  .\scripts\windows\test-proxy.ps1
  .\scripts\windows\test-proxy.ps1 -Url https://example.com
  .\scripts\windows\test-proxy.ps1 -SkipExitCheck
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
$connection = Test-NetConnection -ComputerName $proxyHost -Port ([int]$config['PROXY_PORT']) -WarningAction SilentlyContinue
$connection | Format-List | Out-String | Write-Host
if (-not $connection.TcpTestSucceeded) {
  throw "Proxy endpoint is not reachable: $endpoint"
}

if ($SkipExitCheck) {
  Write-ZtgInfo 'Proxy endpoint is reachable. Exit check skipped.'
  exit 0
}

$curl = Get-Command curl.exe -ErrorAction SilentlyContinue
if (-not $curl) {
  Write-ZtgWarn 'curl.exe was not found. The proxy port is reachable, but the exit URL was not tested.'
  exit 0
}

$curlArgs = @('--silent', '--show-error', '--fail', '--ssl-no-revoke', '--connect-timeout', '10', '--max-time', '30', '--proxy', "http://$endpoint")
$hasUsername = $config.Contains('PROXY_USERNAME') -and -not [string]::IsNullOrWhiteSpace([string]$config['PROXY_USERNAME'])
$hasPassword = $config.Contains('PROXY_PASSWORD') -and -not [string]::IsNullOrWhiteSpace([string]$config['PROXY_PASSWORD'])
if ($hasUsername -and $hasPassword) {
  $curlArgs += @('--proxy-user', "$($config['PROXY_USERNAME']):$($config['PROXY_PASSWORD'])")
}
$curlArgs += $Url

Write-ZtgInfo "Testing proxy exit with $Url"
$response = & $curl.Source @curlArgs
if ($LASTEXITCODE -ne 0) {
  throw "Proxy endpoint is reachable, but the exit URL test failed: $Url"
}
Write-Host $response
Write-ZtgInfo 'Proxy endpoint and exit URL checks passed.'
