[CmdletBinding()]
param(
  [string]$Env = '.env',
  [switch]$Help
)

$ErrorActionPreference = 'Stop'
$lib = Join-Path $PSScriptRoot 'lib'
Import-Module (Join-Path $lib 'Common.psm1') -Force
Import-Module (Join-Path $lib 'Env.psm1') -Force
Import-Module (Join-Path $lib 'Route.psm1') -Force
Import-Module (Join-Path $lib 'ZeroTier.psm1') -Force

function Write-ZtgInfo { param([string]$Message) Write-Host "[INFO] $Message" }

if ($Help) {
  @'
Usage:
  .\scripts\windows\test-network.ps1
  .\scripts\windows\test-network.ps1 -Env path\to\config.env
'@ | Write-Host
  exit 0
}

$config = Read-ZtgEnv -Path $Env
Write-ZtgInfo "Config: $($config['_CONFIG_PATH'])"
Write-ZtgInfo 'ZeroTier status:'
Get-ZtgZeroTierStatus

Write-ZtgInfo 'Route summary:'
Get-ZtgRouteSummary -Config $config | Format-Table | Out-String | Write-Host

foreach ($target in @($config['UBUNTU_ZT_IP'], $config['HOME_PC_ZT_IP'], $config['WORK_PC_ZT_IP'])) {
  Write-ZtgInfo "Ping $target"
  Test-Connection -ComputerName $target -Count 2 -Quiet | ForEach-Object { "Reachable: $_" }
}
