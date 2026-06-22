[CmdletBinding()]
param(
  [ValidateSet('Home','Work')]
  [string]$Role,
  [string]$Env = '.env',
  [switch]$Rollback,
  [switch]$ApplyFirewall,
  [switch]$Help
)

$ErrorActionPreference = 'Stop'
$lib = Join-Path $PSScriptRoot 'lib'
Import-Module (Join-Path $lib 'Common.psm1') -Force
Import-Module (Join-Path $lib 'Env.psm1') -Force
Import-Module (Join-Path $lib 'Firewall.psm1') -Force -DisableNameChecking
Import-Module (Join-Path $lib 'ZeroTier.psm1') -Force

function Write-ZtgInfo { param([string]$Message) Write-Host "[INFO] $Message" }
function Write-ZtgWarn { param([string]$Message) Write-Warning $Message }

if ($Help) {
  @'
Usage:
  .\scripts\windows\setup.ps1 -Role Home
  .\scripts\windows\setup.ps1 -Role Work
  .\scripts\windows\setup.ps1 -Rollback

Options:
  -Env <path>       Override config path. Default: .env in project root.
  -ApplyFirewall    Apply firewall rules after showing the plan.
  -Rollback         Remove firewall rules created by this project.
'@ | Write-Host
  exit 0
}

$config = Read-ZtgEnv -Path $Env
Assert-ZtgEnv -Config $config

if ($Rollback) {
  Write-ZtgInfo 'Removing firewall rules created by this project.'
  Remove-ZtgFirewallRules
  exit 0
}

if (-not $Role) {
  throw 'Role is required. Use -Role Home or -Role Work.'
}

Write-ZtgInfo "Config: $($config['_CONFIG_PATH'])"
Write-ZtgInfo "Role: $Role"
Write-ZtgInfo "Network: $($config['ZEROTIER_NETWORK_ID'])"
Write-ZtgInfo "ZeroTier CLI present: $(Test-ZtgZeroTierCli)"

$plan = New-ZtgFirewallPlan -Config $config -Role $Role
Write-ZtgInfo 'Firewall plan:'
$plan | Format-Table | Out-String | Write-Host

if ($ApplyFirewall) {
  Apply-ZtgFirewallPlan -Plan $plan
  Write-ZtgInfo 'Firewall rules applied.'
} else {
  Write-ZtgWarn 'Firewall rules were not applied. Re-run with -ApplyFirewall after reviewing the plan.'
}
