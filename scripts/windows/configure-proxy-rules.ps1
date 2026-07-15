[CmdletBinding()]
param(
  [string]$Env = '.env',
  [AllowEmptyString()][string]$DirectDomains,
  [AllowEmptyString()][string]$DirectDomainSuffixes,
  [AllowEmptyString()][string]$DirectIpCidrs,
  [AllowEmptyString()][string]$DirectProcessGroups,
  [AllowEmptyString()][string]$DirectProcessNames,
  [AllowEmptyString()][string]$DirectProcessPaths,
  [AllowEmptyString()][string]$DirectProcessPathRegex,
  [switch]$Generate,
  [switch]$Help
)

$ErrorActionPreference = 'Stop'
$lib = Join-Path $PSScriptRoot 'lib'
Import-Module (Join-Path $lib 'Common.psm1') -Force
Import-Module (Join-Path $lib 'Env.psm1') -Force

function Write-ZtgInfo {
  param([Parameter(Mandatory)][string]$Message)
  Write-Host "[INFO] $Message"
}

if ($Help) {
  @'
Usage:
  .\scripts\windows\configure-proxy-rules.ps1
  .\scripts\windows\configure-proxy-rules.ps1 -DirectProcessGroups remote-tools -Generate

Options:
  -Env <path>                  Config path. Default: .env
  -DirectDomains <csv>         Exact domain rules
  -DirectDomainSuffixes <csv>  Domain suffix rules
  -DirectIpCidrs <csv>         IP/CIDR rules
  -DirectProcessGroups <csv>   remote-tools, chat-tools, game-tools
  -DirectProcessNames <csv>    Process executable names
  -DirectProcessPaths <csv>    Full process paths
  -DirectProcessPathRegex <csv> Process path regex rules
  -Generate                    Regenerate PAC and local client config

Run without rule options for an interactive prompt. Press Enter to keep a value.
'@ | Write-Host
  exit 0
}

$config = Read-ZtgEnv -Path $Env
$mapping = [ordered]@{
  DirectDomains = 'DIRECT_DOMAINS'
  DirectDomainSuffixes = 'DIRECT_DOMAIN_SUFFIXES'
  DirectIpCidrs = 'DIRECT_IP_CIDRS'
  DirectProcessGroups = 'DIRECT_PROCESS_GROUPS'
  DirectProcessNames = 'DIRECT_PROCESS_NAMES'
  DirectProcessPaths = 'DIRECT_PROCESS_PATHS'
  DirectProcessPathRegex = 'DIRECT_PROCESS_PATH_REGEX'
}
$labels = @{
  DirectDomains = 'Direct domains, comma separated'
  DirectDomainSuffixes = 'Direct domain suffixes, comma separated'
  DirectIpCidrs = 'Direct IP/CIDR rules, comma separated'
  DirectProcessGroups = 'Direct process groups: remote-tools,chat-tools,game-tools'
  DirectProcessNames = 'Direct process names, comma separated'
  DirectProcessPaths = 'Direct process paths, comma separated'
  DirectProcessPathRegex = 'Direct process path regex rules, comma separated'
}

$hasRuleArgument = $false
foreach ($parameterName in $mapping.Keys) {
  if ($PSBoundParameters.ContainsKey($parameterName)) {
    $hasRuleArgument = $true
    break
  }
}

$values = [ordered]@{}
foreach ($parameterName in $mapping.Keys) {
  $configKey = $mapping[$parameterName]
  if ($PSBoundParameters.ContainsKey($parameterName)) {
    $values[$configKey] = [string](Get-Variable -Name $parameterName -ValueOnly)
    continue
  }
  if ($hasRuleArgument) {
    continue
  }

  $current = if ($config.Contains($configKey)) { [string]$config[$configKey] } else { '' }
  $answer = Read-Host "$($labels[$parameterName]) [$current]"
  if ([string]::IsNullOrWhiteSpace($answer)) {
    $answer = $current
  }
  $values[$configKey] = [string]$answer
}

if ($values.Count -eq 0) {
  throw 'No proxy rule value was provided.'
}

$target = Set-ZtgEnvValues -Path $Env -Values $values
Write-ZtgInfo "Proxy rules updated: $target"

if ($Generate) {
  & (Join-Path $PSScriptRoot 'generate-proxy-pac.ps1') -Env $Env
  & (Join-Path $PSScriptRoot 'generate-client-rules.ps1') -Env $Env
  Write-ZtgInfo 'PAC and local client config regenerated.'
} else {
  Write-ZtgInfo 'Next: run generate-proxy-pac.ps1 or generate-client-rules.ps1 as needed.'
}
