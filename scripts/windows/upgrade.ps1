[CmdletBinding()]
param(
  [switch]$Apply,
  [string]$Rollback,
  [string]$DataRoot,
  [switch]$Help
)

$ErrorActionPreference = 'Stop'
$lib = Join-Path $PSScriptRoot 'lib'
Import-Module (Join-Path $lib 'Upgrade.psm1') -Force
Import-Module (Join-Path $lib 'State.psm1') -Force
Import-Module (Join-Path $lib 'Common.psm1') -Force

if ($Help) {
  @'
Usage:
  .\scripts\windows\upgrade.ps1
  .\scripts\windows\upgrade.ps1 -Apply
  .\scripts\windows\upgrade.ps1 -Rollback <backup-id>

Without -Apply the command is preview-only. Apply writes project management state
but does not change firewall, PAC, local rules, Scheduled Tasks, v2rayN, or listeners.
'@ | Write-Host
  exit 0
}

$projectRoot = Get-ZtgProjectRoot
$version = Get-ZtgProjectVersion
$head = Get-ZtgSourceHead
$fingerprint = Get-ZtgWindowsInstallationFingerprint -ProjectRoot $projectRoot
$data = Get-ZtgDataRoot -Root $DataRoot
$statePath = Get-ZtgStatePath -Name 'installation' -Root $data
$installed = Read-ZtgJsonState -Name 'installation' -Root $data -ExpectedObjectType 'installation' -ExpectedObjectName 'host'

Write-ZtgInfo "Source HEAD: $head"
Write-ZtgInfo "Target version: $version"
Write-ZtgInfo "Installed management version: $(if ($installed) { $installed.lastAppliedVersion } else { 'not-recorded' })"
Write-ZtgInfo "Installation fingerprint: $fingerprint"
Write-ZtgInfo "State: $statePath"
Write-ZtgInfo 'New capabilities after upgrade: disabled'

if ($fingerprint -ne 'source-only-windows') {
  throw "Installation ownership is unknown: $fingerprint. No files were changed."
}

if ($Rollback) {
  if (-not $Apply) { throw '-Rollback requires -Apply.' }
  $backup = Resolve-ZtgWindowsBackupDirectory -BackupId $Rollback -DataRoot $data
  Restore-ZtgWindowsManagementState -BackupDirectory $backup -DataRoot $data
  Write-ZtgInfo "Management state restored from $backup"
  exit 0
}

$backupId = ([DateTime]::UtcNow.ToString('yyyyMMddTHHmmssZ')) + '-' + $head
$backupDirectory = Join-Path (Join-Path $data 'backups') $backupId
if (Test-Path -LiteralPath $backupDirectory) { throw "Backup destination already exists: $backupDirectory" }
Write-ZtgInfo "Backup destination: $backupDirectory"
Write-ZtgInfo 'Plan: snapshot runtime -> back up project files -> verify runtime unchanged -> record management version'
Write-ZtgInfo 'Forbidden: firewall/PAC/client JSON/task/v2rayN/process/listener changes.'

if (-not $Apply) {
  Write-ZtgInfo '[PREVIEW] No directory, state, process, listener, task, firewall, PAC, or proxy configuration was changed.'
  exit 0
}

$identity = [Security.Principal.WindowsIdentity]::GetCurrent()
$principal = New-Object Security.Principal.WindowsPrincipal($identity)
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
  throw 'Run an administrator PowerShell to apply the management upgrade.'
}

$before = Get-ZtgWindowsRuntimeSnapshot -ProjectRoot $projectRoot
New-ZtgWindowsUpgradeBackup -BackupDirectory $backupDirectory -ProjectRoot $projectRoot -DataRoot $data
$after = Get-ZtgWindowsRuntimeSnapshot -ProjectRoot $projectRoot
if ($before -ne $after) {
  throw "Runtime invariant changed. State was not committed. Backup: $backupDirectory"
}

$state = New-ZtgManagedState -ObjectType installation -ObjectName host -Version $version -Properties @{
  installationFingerprint = $fingerprint
  sourceHead = $head
}
Write-ZtgJsonState -Name installation -Value $state -Root $data | Out-Null
Write-ZtgInfo 'Management upgrade completed without changing existing runtime.'
Write-ZtgInfo "Rollback: .\scripts\windows\upgrade.ps1 -Rollback $backupId -Apply"
Write-ZtgInfo 'Next: .\scripts\windows\show-diagnostics.ps1'
