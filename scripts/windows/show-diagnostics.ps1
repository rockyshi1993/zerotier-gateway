[CmdletBinding()]
param(
  [string]$FindProcess,
  [string]$FindProcessPath,
  [switch]$Help
)

$ErrorActionPreference = 'Stop'
$lib = Join-Path $PSScriptRoot 'lib'
Import-Module (Join-Path $lib 'Diagnostics.psm1') -Force

if ($Help -or (-not $FindProcess -and -not $FindProcessPath)) {
  @'
Usage:
  .\scripts\windows\show-diagnostics.ps1 -FindProcess "remote"
  .\scripts\windows\show-diagnostics.ps1 -FindProcessPath "C:\Program Files\RemoteTool"
'@ | Write-Host
  exit 0
}

if ($FindProcess) {
  Find-ZtgProcess -Pattern $FindProcess | Format-Table -AutoSize
}

if ($FindProcessPath) {
  Find-ZtgProcessPath -Path $FindProcessPath | Format-Table -AutoSize
}
