[CmdletBinding()]
param(
  [string]$SingBoxPath,
  [string]$DataRoot,
  [switch]$Once
)

$ErrorActionPreference = 'Stop'
$lib = Join-Path $PSScriptRoot 'lib'
Import-Module (Join-Path $lib 'ProxyPool.psm1') -Force
Import-Module (Join-Path $lib 'Upgrade.psm1') -Force
Import-Module (Join-Path $lib 'State.psm1') -Force
Import-Module (Join-Path $lib 'Common.psm1') -Force

$mutex = New-Object Threading.Mutex($false, 'Local\ZeroTierGatewayProxySelector')
$locked = $false

function Write-ControllerLog {
  param([string]$Message)
  $paths = Get-ZtgProxyRuntimePaths -DataRoot $DataRoot
  [System.IO.Directory]::CreateDirectory($paths.Directory) | Out-Null
  $logPath = Join-Path $paths.Directory 'selector.log'
  if ((Test-Path -LiteralPath $logPath -PathType Leaf) -and (Get-Item -LiteralPath $logPath).Length -ge 1MB) {
    $backupPath = "$logPath.1"
    Remove-Item -LiteralPath $backupPath -Force -ErrorAction SilentlyContinue
    Move-Item -LiteralPath $logPath -Destination $backupPath -Force
  }
  $line = "{0} {1}{2}" -f ([DateTime]::UtcNow.ToString('o')),$Message,[Environment]::NewLine
  [System.IO.File]::AppendAllText($logPath, $line, (New-Object Text.UTF8Encoding($false)))
}

try {
  $locked = $mutex.WaitOne(0)
  if (-not $locked) { throw 'Another proxy selector controller is already running.' }
  $resolvedSingBox = Get-ZtgSingBoxPath -Path $SingBoxPath
  $version = Get-ZtgProjectVersion
  do {
    $cycleStarted = [DateTime]::UtcNow
    $poolLock = Enter-ZtgProxyPoolLock -DataRoot $DataRoot
    try {
      $pool = Get-ZtgProxyPool -DataRoot $DataRoot -Version $version
      if (-not [bool]$pool.enabled) { Write-ControllerLog 'Pool is disabled; controller exits.'; break }
    $previousSelected = [string]$pool.selectedNode
    $results = Invoke-ZtgProxyHealthBatch -Nodes @($pool.nodes) -Url ([string]$pool.probeUrl) -TimeoutSeconds ([int]$pool.timeoutSeconds) -MaxConcurrency 4
    foreach ($node in @($pool.nodes)) {
      if (-not [bool]$node.enabled) { $node.healthState = 'disabled'; continue }
      $result = @($results | Where-Object { $_.Name -eq $node.name } | Select-Object -First 1)
      if ($result.Count -eq 0) {
        Update-ZtgProxyNodeHealth -Node $node -Success $false -ErrorMessage 'probe produced no result' -FailureThreshold ([int]$pool.failureThreshold) -RecoveryThreshold ([int]$pool.recoveryThreshold) | Out-Null
      } else {
        Update-ZtgProxyNodeHealth -Node $node -Success ([bool]$result[0].Success) -LatencyMs ([int]$result[0].LatencyMs) -ErrorMessage ([string]$result[0].Error) -FailureThreshold ([int]$pool.failureThreshold) -RecoveryThreshold ([int]$pool.recoveryThreshold) | Out-Null
      }
    }
    $selection = Select-ZtgProxyNode -Pool $pool
    $pool = $selection.Pool
    $paths = Get-ZtgProxyRuntimePaths -DataRoot $DataRoot
    $runtimeMissing = -not (Test-ZtgProxyRuntimeRunning -DataRoot $DataRoot)
    $listenerMissing = -not (Test-ZtgTcpPort -Address '127.0.0.1' -Port ([int]$pool.localPort) -TimeoutMilliseconds 200)
    $logBudgetExceeded = -not (Test-ZtgProxyRuntimeLogBudget -DataRoot $DataRoot)
    $configChanged = -not (Test-ZtgProxyRuntimeConfigCurrent -Pool $pool -SelectedNode $selection.SelectedNode -DataRoot $DataRoot)
    try {
      if ($selection.Changed -or $runtimeMissing -or $listenerMissing -or $logBudgetExceeded -or $configChanged) {
        Apply-ZtgProxyRuntime -Pool $pool -SelectedNode $selection.SelectedNode -SingBoxPath $resolvedSingBox -DataRoot $DataRoot
        Write-ControllerLog ("Runtime applied; selected={0}" -f $(if ($selection.SelectedNode) { $selection.SelectedNode.name } else { 'none/fail-closed' }))
      }
      if ($pool.PSObject.Properties.Name -contains 'lastControllerError') { $pool.lastControllerError = $null } else { $pool | Add-Member -NotePropertyName lastControllerError -NotePropertyValue $null }
    } catch {
      $pool.selectedNode = if ($previousSelected) { $previousSelected } else { $null }
      if ($pool.PSObject.Properties.Name -contains 'lastControllerError') { $pool.lastControllerError = $_.Exception.Message } else { $pool | Add-Member -NotePropertyName lastControllerError -NotePropertyValue $_.Exception.Message }
      Write-ControllerLog ("Apply failed: {0}" -f $_.Exception.Message)
    }
      Save-ZtgProxyPool -Pool $pool -DataRoot $DataRoot | Out-Null
      $elapsed = ([DateTime]::UtcNow - $cycleStarted).TotalSeconds
      $sleep = [Math]::Max(1, [int]$pool.intervalSeconds - [int][Math]::Floor($elapsed))
    } finally {
      Exit-ZtgProxyPoolLock -LockHandle $poolLock
    }
    if ($Once) { break }
    Start-Sleep -Seconds $sleep
  } while ($true)
} catch {
  Write-ControllerLog ("Controller stopped: {0}" -f $_.Exception.Message)
  throw
} finally {
  if ($locked) { $mutex.ReleaseMutex() }
  $mutex.Dispose()
}
