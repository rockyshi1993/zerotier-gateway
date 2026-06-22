[CmdletBinding()]
param(
  [string]$Env = '.env',
  [string]$Output = 'artifacts\windows-local-client.json',
  [switch]$Help
)

$ErrorActionPreference = 'Stop'
$lib = Join-Path $PSScriptRoot 'lib'
Import-Module (Join-Path $lib 'Common.psm1') -Force
Import-Module (Join-Path $lib 'Env.psm1') -Force
Import-Module (Join-Path $lib 'ProxyRules.psm1') -Force

function Get-ZtgProjectRoot { return (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path }
function Write-ZtgInfo { param([string]$Message) Write-Host "[INFO] $Message" }

if ($Help) {
  @'
Usage:
  .\scripts\windows\generate-client-rules.ps1
  .\scripts\windows\generate-client-rules.ps1 -Output artifacts\windows-local-client.json
'@ | Write-Host
  exit 0
}

$config = Read-ZtgEnv -Path $Env
$content = New-ZtgClientRulesContent -Config $config
$target = if ([System.IO.Path]::IsPathRooted($Output)) { $Output } else { Join-Path (Get-ZtgProjectRoot) $Output }
New-Item -ItemType Directory -Force -Path (Split-Path -Parent $target) | Out-Null
Set-Content -LiteralPath $target -Value $content -Encoding UTF8
Write-ZtgInfo "Client rules generated: $target"
