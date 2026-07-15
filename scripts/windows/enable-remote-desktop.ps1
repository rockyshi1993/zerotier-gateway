[CmdletBinding()]
param(
  [switch]$Apply,
  [switch]$Help
)

$ErrorActionPreference = 'Stop'
$lib = Join-Path $PSScriptRoot 'lib'
Import-Module (Join-Path $lib 'Common.psm1') -Force

if ($Help) {
  @'
Usage:
  .\scripts\windows\enable-remote-desktop.ps1
  .\scripts\windows\enable-remote-desktop.ps1 -Apply

Without -Apply the script only reports the current state and planned change.
Use -Apply in an administrator PowerShell on the PC that will accept RDP connections.
'@ | Write-Host
  exit 0
}

function Test-ZtgAdministrator {
  $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
  $principal = New-Object Security.Principal.WindowsPrincipal($identity)
  return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

$windowsInfoPath = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion'
$terminalServerPath = 'HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server'
$rdpTcpPath = 'HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp'
$edition = [string](Get-ItemPropertyValue -Path $windowsInfoPath -Name EditionID)
$productName = [string](Get-ItemPropertyValue -Path $windowsInfoPath -Name ProductName)
$supportedHost = $edition -match '(Professional|Enterprise|Education|Server|IoTEnterprise)'
$denyConnections = [int](Get-ItemPropertyValue -Path $terminalServerPath -Name fDenyTSConnections)
$enabled = $denyConnections -eq 0

Write-ZtgInfo "Windows: $productName ($edition)"
if (-not $supportedHost) {
  Write-ZtgWarn 'This Windows edition cannot act as a Microsoft Remote Desktop host. Windows Home can still be an RDP client or use another remote-control tool.'
  if ($Apply) {
    throw 'Remote Desktop host is not supported by this Windows edition.'
  }
  exit 0
}

if ($enabled) {
  Write-ZtgInfo 'Remote Desktop host is already enabled.'
} else {
  Write-ZtgInfo 'Remote Desktop host is disabled.'
}

if (-not $Apply) {
  Write-ZtgInfo 'Preview only. Run again with -Apply to enable RDP and keep Network Level Authentication enabled.'
  Write-ZtgInfo 'The project firewall rule is applied separately with setup.ps1 -Role Home|Work -ApplyFirewall.'
  exit 0
}

if (-not (Test-ZtgAdministrator)) {
  throw 'Administrator PowerShell is required. Reopen PowerShell with Run as administrator.'
}

Set-ItemProperty -Path $terminalServerPath -Name fDenyTSConnections -Type DWord -Value 0
Set-ItemProperty -Path $rdpTcpPath -Name UserAuthentication -Type DWord -Value 1
Start-Service -Name TermService

$denyConnections = [int](Get-ItemPropertyValue -Path $terminalServerPath -Name fDenyTSConnections)
if ($denyConnections -ne 0) {
  throw 'Remote Desktop setting did not persist.'
}

Write-ZtgInfo 'Remote Desktop host enabled with Network Level Authentication.'
Write-ZtgInfo 'Next: apply the project firewall rule, then verify port 3389 from the other ZeroTier PC.'
