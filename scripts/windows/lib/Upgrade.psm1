Set-StrictMode -Version Latest

Import-Module (Join-Path $PSScriptRoot 'Common.psm1') -Force
Import-Module (Join-Path $PSScriptRoot 'State.psm1') -Force

function Get-ZtgProjectVersion {
  $versionPath = Join-Path (Get-ZtgProjectRoot) 'VERSION'
  if (-not (Test-Path -LiteralPath $versionPath)) { throw "VERSION file not found: $versionPath" }
  return (Get-Content -LiteralPath $versionPath -Raw).Trim()
}

function Get-ZtgSourceHead {
  try {
    $head = & git -C (Get-ZtgProjectRoot) rev-parse --short=12 HEAD 2>$null
    if ($LASTEXITCODE -eq 0 -and $head) { return ([string]$head).Trim() }
  } catch { }
  return 'source-archive'
}

function Get-ZtgWindowsInstallationFingerprint {
  param([string]$ProjectRoot = (Get-ZtgProjectRoot))
  if (-not (Test-Path -LiteralPath (Join-Path $ProjectRoot 'VERSION'))) { return 'unknown' }
  return 'source-only-windows'
}

function Get-ZtgFileFingerprint {
  param([Parameter(Mandatory)][string]$Path)
  if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return 'missing' }
  return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

function Get-ZtgWindowsRuntimeSnapshot {
  param([string]$ProjectRoot = (Get-ZtgProjectRoot))
  $files = @('.env','artifacts/proxy.pac','artifacts/sing-box-windows-client.json')
  $watchedPorts = @(10808, 20808)
  $envPath = Join-Path $ProjectRoot '.env'
  if (Test-Path -LiteralPath $envPath) {
    Get-Content -LiteralPath $envPath | ForEach-Object {
      if ($_ -match '^\s*(PROXY_PORT|LOCAL_PROXY_PORT)\s*=\s*([0-9]+)\s*$') {
        $watchedPorts += [int]$Matches[2]
      }
    }
  }
  $watchedPorts = @($watchedPorts | Sort-Object -Unique)
  $facts = [ordered]@{}
  foreach ($relative in $files) {
    $facts["file:$relative"] = Get-ZtgFileFingerprint -Path (Join-Path $ProjectRoot $relative)
  }
  try {
    $rules = @(Get-NetFirewallRule -ErrorAction Stop | Where-Object { $_.DisplayName -like 'ZeroTier Gateway*' } | Sort-Object DisplayName | Select-Object DisplayName,Enabled,Direction,Action)
    $facts.firewall = (($rules | ConvertTo-Json -Compress -Depth 4) | Out-String).Trim()
  } catch { $facts.firewall = 'unavailable' }
  try {
    $tasks = @(Get-ScheduledTask -TaskPath '\ZeroTierGateway\' -ErrorAction SilentlyContinue | Sort-Object TaskName | Select-Object TaskName,State)
    $facts.tasks = (($tasks | ConvertTo-Json -Compress -Depth 4) | Out-String).Trim()
  } catch { $facts.tasks = 'unavailable' }
  try {
    $listeners = @(Get-NetTCPConnection -State Listen -ErrorAction Stop | Where-Object { $watchedPorts -contains [int]$_.LocalPort } | Sort-Object LocalAddress,LocalPort | Select-Object LocalAddress,LocalPort,OwningProcess)
    $facts.listeners = (($listeners | ConvertTo-Json -Compress -Depth 4) | Out-String).Trim()
  } catch { $facts.listeners = 'unavailable' }
  return (($facts | ConvertTo-Json -Compress -Depth 5) | Out-String).Trim()
}

function New-ZtgWindowsUpgradeBackup {
  param(
    [Parameter(Mandatory)][string]$BackupDirectory,
    [string]$ProjectRoot = (Get-ZtgProjectRoot),
    [string]$DataRoot
  )
  [System.IO.Directory]::CreateDirectory($BackupDirectory) | Out-Null
  foreach ($relative in @('.env','artifacts/proxy.pac','artifacts/sing-box-windows-client.json')) {
    $source = Join-Path $ProjectRoot $relative
    if (-not (Test-Path -LiteralPath $source -PathType Leaf)) { continue }
    $target = Join-Path $BackupDirectory (Join-Path 'project' $relative)
    [System.IO.Directory]::CreateDirectory((Split-Path -Parent $target)) | Out-Null
    Copy-Item -LiteralPath $source -Destination $target -Force
  }
  $stateDirectory = Join-Path (Get-ZtgDataRoot -Root $DataRoot) 'state'
  if (Test-Path -LiteralPath $stateDirectory) {
    $target = Join-Path $BackupDirectory 'state'
    [System.IO.Directory]::CreateDirectory($target) | Out-Null
    Get-ChildItem -LiteralPath $stateDirectory -Force | Copy-Item -Destination $target -Recurse -Force
  }
}

function Resolve-ZtgWindowsBackupDirectory {
  param(
    [Parameter(Mandatory)][string]$BackupId,
    [string]$DataRoot
  )
  if ($BackupId -notmatch '^[A-Za-z0-9][A-Za-z0-9._-]{0,127}$') {
    throw "Invalid backup id: $BackupId"
  }
  $root = Join-Path (Get-ZtgDataRoot -Root $DataRoot) 'backups'
  if (-not (Test-Path -LiteralPath $root -PathType Container)) { throw "Backup root not found: $root" }
  $resolvedRoot = (Resolve-Path -LiteralPath $root).Path.TrimEnd([IO.Path]::DirectorySeparatorChar, [IO.Path]::AltDirectorySeparatorChar)
  $candidate = Join-Path $resolvedRoot $BackupId
  if (-not (Test-Path -LiteralPath $candidate -PathType Container)) { throw "Backup not found: $candidate" }
  $item = Get-Item -LiteralPath $candidate -Force
  if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
    throw "Backup links and junctions are not accepted: $candidate"
  }
  $resolvedCandidate = (Resolve-Path -LiteralPath $candidate).Path
  if ([IO.Path]::GetFullPath((Split-Path -Parent $resolvedCandidate)) -ne [IO.Path]::GetFullPath($resolvedRoot)) {
    throw "Backup must be a direct child of the project backup root: $candidate"
  }
  return $resolvedCandidate
}

function Restore-ZtgWindowsManagementState {
  param(
    [Parameter(Mandatory)][string]$BackupDirectory,
    [string]$DataRoot
  )
  $stateDirectory = Join-Path (Get-ZtgDataRoot -Root $DataRoot) 'state'
  $backupState = Join-Path $BackupDirectory 'state'
  $installation = Join-Path $stateDirectory 'installation.json'
  if (Test-Path -LiteralPath $installation) { Remove-Item -LiteralPath $installation -Force }
  if (Test-Path -LiteralPath $backupState) {
    [System.IO.Directory]::CreateDirectory($stateDirectory) | Out-Null
    Get-ChildItem -LiteralPath $backupState -Force | Copy-Item -Destination $stateDirectory -Recurse -Force
  }
}

Export-ModuleMember -Function Get-ZtgProjectVersion,Get-ZtgSourceHead,Get-ZtgWindowsInstallationFingerprint,Get-ZtgWindowsRuntimeSnapshot,New-ZtgWindowsUpgradeBackup,Resolve-ZtgWindowsBackupDirectory,Restore-ZtgWindowsManagementState
