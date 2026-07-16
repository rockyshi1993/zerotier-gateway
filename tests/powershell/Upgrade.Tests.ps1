$ErrorActionPreference = 'Stop'
$root = Resolve-Path (Join-Path $PSScriptRoot '..\..')
Import-Module (Join-Path $root 'scripts\windows\lib\Upgrade.psm1') -Force

if ((Get-ZtgProjectVersion) -ne '1.4.0-dev') { throw 'Project version mismatch.' }
if ((Get-ZtgWindowsInstallationFingerprint -ProjectRoot $root) -ne 'source-only-windows') { throw 'Unexpected Windows fingerprint.' }

$before = Get-ZtgWindowsRuntimeSnapshot -ProjectRoot $root
$temp = Join-Path ([System.IO.Path]::GetTempPath()) ('ztg-upgrade-test-' + [guid]::NewGuid().ToString('N'))
try {
  New-ZtgWindowsUpgradeBackup -BackupDirectory (Join-Path $temp 'backup') -ProjectRoot $root -DataRoot (Join-Path $temp 'data')
  $after = Get-ZtgWindowsRuntimeSnapshot -ProjectRoot $root
  if ($before -ne $after) { throw 'Backup changed the Windows runtime snapshot.' }
  $source = Get-Content -LiteralPath (Join-Path $root 'scripts\windows\upgrade.ps1') -Raw
  foreach ($forbidden in @('New-NetFirewallRule','Remove-NetFirewallRule','Register-ScheduledTask','Unregister-ScheduledTask','generate-proxy-pac.ps1','generate-client-rules.ps1')) {
    if ($source.Contains($forbidden)) { throw "Default upgrade source contains forbidden mutation: $forbidden" }
  }
  $data = Join-Path $temp 'data'
  $stateDirectory = Join-Path $data 'state'
  $backupDirectory = Join-Path (Join-Path $data 'backups') 'valid-id'
  [IO.Directory]::CreateDirectory((Join-Path $backupDirectory 'state')) | Out-Null
  [IO.Directory]::CreateDirectory($stateDirectory) | Out-Null
  [IO.File]::WriteAllText((Join-Path $stateDirectory 'installation.json'), '{"current":true}')
  [IO.File]::WriteAllText((Join-Path $backupDirectory 'state\proxy-pool.json'), '{"sibling":true}')
  Restore-ZtgWindowsManagementState -BackupDirectory $backupDirectory -DataRoot $data
  if (Test-Path -LiteralPath (Join-Path $stateDirectory 'installation.json')) { throw 'Windows rollback did not restore installation state absence.' }
  if (-not (Test-Path -LiteralPath (Join-Path $stateDirectory 'proxy-pool.json'))) { throw 'Windows sibling state was not restored.' }
  if ((Resolve-ZtgWindowsBackupDirectory -BackupId 'valid-id' -DataRoot $data) -ne (Resolve-Path -LiteralPath $backupDirectory).Path) { throw 'Valid backup id did not resolve.' }
  $traversalRejected = $false
  try { Resolve-ZtgWindowsBackupDirectory -BackupId '..\foreign' -DataRoot $data | Out-Null } catch { $traversalRejected = $true }
  if (-not $traversalRejected) { throw 'Windows rollback traversal id was accepted.' }
  Write-Host 'Upgrade tests passed.'
} finally {
  if (Test-Path -LiteralPath $temp) { Remove-Item -LiteralPath $temp -Recurse -Force }
}
