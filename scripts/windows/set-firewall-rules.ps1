[CmdletBinding()]
param(
  [ValidateSet('Home','Work')]
  [string]$Role,
  [string]$Env = '.env',
  [switch]$Apply,
  [switch]$Remove,
  [switch]$Help
)

$ErrorActionPreference = 'Stop'
$lib = Join-Path $PSScriptRoot 'lib'
Import-Module (Join-Path $lib 'Common.psm1') -Force
Import-Module (Join-Path $lib 'Env.psm1') -Force
Import-Module (Join-Path $lib 'Firewall.psm1') -Force -DisableNameChecking

function Write-ZtgInfo { param([string]$Message) Write-Host "[INFO] $Message" }
function Write-ZtgWarn { param([string]$Message) Write-Warning $Message }

if ($Help) {
  @'
Usage:
  .\scripts\windows\set-firewall-rules.ps1 -Role Home
  .\scripts\windows\set-firewall-rules.ps1 -Role Work -Apply
  .\scripts\windows\set-firewall-rules.ps1 -Remove
'@ | Write-Host
  exit 0
}

if ($Remove) {
  Remove-ZtgFirewallRules
  Write-ZtgInfo 'Firewall rules removed.'
  exit 0
}

if (-not $Role) {
  throw 'Role is required unless -Remove is used.'
}

$config = Read-ZtgEnv -Path $Env
$plan = New-ZtgFirewallPlan -Config $config -Role $Role
$plan | Format-Table | Out-String | Write-Host

if ($Apply) {
  Apply-ZtgFirewallPlan -Plan $plan
  Write-ZtgInfo 'Firewall rules applied.'
} else {
  Write-ZtgWarn 'Preview only. Add -Apply to create these firewall rules.'
}
