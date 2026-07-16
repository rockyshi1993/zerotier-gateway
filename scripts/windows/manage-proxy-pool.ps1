[CmdletBinding()]
param(
  [Parameter(Mandatory)][ValidateSet('Add','Update','List','Status','Test','Enable','Disable','Remove')][string]$Action,
  [string]$Name,
  [string]$Server,
  [int]$Port,
  [AllowEmptyString()][string]$Username,
  [AllowEmptyString()][string]$Password,
  [ValidateSet('Enabled','Disabled')][string]$NodeState,
  [switch]$SaveDisabled,
  [int]$LocalPort,
  [string]$ProbeUrl,
  [string]$SingBoxPath,
  [string]$DataRoot,
  [switch]$Apply,
  [switch]$ConfirmRemoval
)

$ErrorActionPreference = 'Stop'
$lib = Join-Path $PSScriptRoot 'lib'
Import-Module (Join-Path $lib 'ProxyPool.psm1') -Force
Import-Module (Join-Path $lib 'Upgrade.psm1') -Force
Import-Module (Join-Path $lib 'State.psm1') -Force
Import-Module (Join-Path $lib 'Common.psm1') -Force

function Assert-Administrator {
  $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
  $principal = New-Object Security.Principal.WindowsPrincipal($identity)
  if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    throw 'Run an administrator PowerShell for this Apply action.'
  }
}

function Set-DataDirectoryAcl {
  param([Parameter(Mandatory)][string]$Root)
  [System.IO.Directory]::CreateDirectory($Root) | Out-Null
  $user = [Security.Principal.WindowsIdentity]::GetCurrent().Name
  & icacls.exe $Root '/inheritance:r' '/grant:r' "${user}:(OI)(CI)F" '*S-1-5-18:(OI)(CI)F' '*S-1-5-32-544:(OI)(CI)F' '/T' '/C' | Out-Null
  if ($LASTEXITCODE -ne 0) { throw "Failed to protect project state ACL: $Root" }
}

function Read-SecretValue {
  param([Parameter(Mandatory)][string]$Prompt)
  $secure = Read-Host $Prompt -AsSecureString
  $pointer = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure)
  try { return [Runtime.InteropServices.Marshal]::PtrToStringBSTR($pointer) }
  finally { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($pointer) }
}

$version = Get-ZtgProjectVersion
$pool = Get-ZtgProxyPool -DataRoot $DataRoot -Version $version
$data = Get-ZtgDataRoot -Root $DataRoot

switch ($Action) {
  'Add' {
    if (-not $Name) { $Name = Read-Host 'Node name' }
    if (-not $Server) { $Server = Read-Host 'SOCKS server address' }
    if (-not $Port) { $Port = [int](Read-Host 'SOCKS port') }
    if (-not $PSBoundParameters.ContainsKey('Username')) { $Username = Read-Host 'Username (Enter for none)' }
    if ($Username -and -not $PSBoundParameters.ContainsKey('Password')) { $Password = Read-SecretValue -Prompt 'Password' }
    if (-not $Password) { $Password = '' }
    $reachable = Test-ZtgTcpPort -Address $Server -Port $Port
    $enabled = -not $SaveDisabled
    if (-not $reachable -and $enabled) {
      throw 'The node TCP endpoint is not reachable. Retry when available, or use -SaveDisabled to store it disabled.'
    }
    $candidate = Add-ZtgProxyNode -Pool $pool -Name $Name -Server $Server -Port $Port -Username $Username -Password $Password -Enabled $enabled
    Write-ZtgInfo "Plan: add node $Name -> ${Server}:$Port; enabled=$enabled; tcpReachable=$reachable"
    if (-not $Apply) { Write-ZtgWarn 'Preview only. Re-run with -Apply to save this node.'; break }
    Assert-Administrator
    Set-DataDirectoryAcl -Root $data
    $poolLock = Enter-ZtgProxyPoolLock -DataRoot $DataRoot
    try {
      $latestPool = Get-ZtgProxyPool -DataRoot $DataRoot -Version $version
      $candidate = Add-ZtgProxyNode -Pool $latestPool -Name $Name -Server $Server -Port $Port -Username $Username -Password $Password -Enabled $enabled
      Save-ZtgProxyPool -Pool $candidate -DataRoot $DataRoot | Out-Null
    } finally {
      Exit-ZtgProxyPoolLock -LockHandle $poolLock
    }
    Write-ZtgInfo "Node saved. Next: .\scripts\windows\manage-proxy-pool.ps1 -Action Test -Name $Name"
  }
  'Update' {
    if (-not $Name) { throw '-Name is required for Update.' }
    $parameters = @{ Pool = $pool; Name = $Name }
    if ($PSBoundParameters.ContainsKey('Server')) { $parameters.Server = $Server }
    if ($PSBoundParameters.ContainsKey('Port')) { $parameters.Port = $Port }
    if ($PSBoundParameters.ContainsKey('Username')) { $parameters.Username = $Username }
    if ($PSBoundParameters.ContainsKey('Password')) { $parameters.Password = $Password }
    if ($NodeState) { $parameters.Enabled = ($NodeState -eq 'Enabled') }
    $candidate = Update-ZtgProxyNode @parameters
    $updatedNode = @($candidate.nodes | Where-Object name -eq $Name | Select-Object -First 1)[0]
    $reachable = Test-ZtgTcpPort -Address ([string]$updatedNode.host) -Port ([int]$updatedNode.port)
    if ([bool]$updatedNode.enabled -and -not $reachable) { throw 'The updated node TCP endpoint is not reachable. Retry when available, or update it with -NodeState Disabled.' }
    Write-ZtgInfo "Plan: update node $Name; enabled=$($updatedNode.enabled); tcpReachable=$reachable; generation=$($candidate.generation)"
    if (-not $Apply) { Write-ZtgWarn 'Preview only. Re-run with -Apply to save.'; break }
    Assert-Administrator
    Set-DataDirectoryAcl -Root $data
    $poolLock = Enter-ZtgProxyPoolLock -DataRoot $DataRoot
    try {
      $latestPool = Get-ZtgProxyPool -DataRoot $DataRoot -Version $version
      $parameters.Pool = $latestPool
      $candidate = Update-ZtgProxyNode @parameters
      $updatedNode = @($candidate.nodes | Where-Object name -eq $Name | Select-Object -First 1)[0]
      $reachable = Test-ZtgTcpPort -Address ([string]$updatedNode.host) -Port ([int]$updatedNode.port)
      if ([bool]$updatedNode.enabled -and -not $reachable) { throw 'The updated node TCP endpoint is not reachable. Retry when available, or update it with -NodeState Disabled.' }
      Save-ZtgProxyPool -Pool $candidate -DataRoot $DataRoot | Out-Null
    } finally {
      Exit-ZtgProxyPoolLock -LockHandle $poolLock
    }
    Write-ZtgInfo 'Node updated. The running selector will consume the new generation on its next cycle.'
  }
  'List' {
    if (@($pool.nodes).Count -eq 0) { Write-ZtgWarn 'No proxy nodes are configured.'; break }
    $pool.nodes | Select-Object name,host,port,enabled,healthState,lastLatencyMs,lastCheckedAt,lastError | Format-Table -AutoSize
  }
  'Status' {
    $paths = Get-ZtgProxyRuntimePaths -DataRoot $DataRoot
    $task = Get-ScheduledTask -TaskName 'ProxySelector' -TaskPath '\ZeroTierGateway\' -ErrorAction SilentlyContinue
    $pidRecord = $null
    if (Test-Path -LiteralPath $paths.Pid) { $pidRecord = Get-Content -LiteralPath $paths.Pid -Raw | ConvertFrom-Json }
    Write-ZtgInfo "Enabled: $($pool.enabled)"
    Write-ZtgInfo "Local entry: 127.0.0.1:$($pool.localPort) (SOCKS5 + HTTP)"
    Write-ZtgInfo "Selected node: $(if ($pool.selectedNode) { $pool.selectedNode } else { 'none; fail-closed' })"
    Write-ZtgInfo "Scheduled Task: $(if ($task) { $task.State } else { 'not registered' })"
    Write-ZtgInfo "sing-box PID: $(if ($pidRecord) { $pidRecord.pid } else { 'not running' })"
    Write-ZtgInfo "Runtime ownership/running: $(Test-ZtgProxyRuntimeRunning -DataRoot $DataRoot)"
    Write-ZtgInfo "Last controller error: $(if ($pool.PSObject.Properties.Name -contains 'lastControllerError' -and $pool.lastControllerError) { $pool.lastControllerError } else { 'none' })"
    $pool.nodes | Select-Object name,enabled,healthState,lastLatencyMs,lastCheckedAt,lastError | Format-Table -AutoSize
  }
  'Test' {
    $targets = if ($Name) { @($pool.nodes | Where-Object { $_.name -eq $Name }) } else { @($pool.nodes) }
    if ($targets.Count -eq 0) { throw 'No matching proxy nodes to test.' }
    $results = foreach ($node in $targets) {
      if (-not $node.enabled) {
        [pscustomobject]@{ Name=$node.name; Success=$false; LatencyMs=$null; Error='disabled' }
      } else {
        Test-ZtgProxyNode -Node $node -Url ([string]$pool.probeUrl) -TimeoutSeconds ([int]$pool.timeoutSeconds)
      }
    }
    $results | Format-Table -AutoSize
    if (@($results | Where-Object { -not $_.Success }).Count -gt 0) { throw 'One or more proxy exit checks failed.' }
  }
  'Enable' {
    if (@($pool.nodes | Where-Object { $_.enabled }).Count -eq 0) { throw 'Add at least one enabled node before Enable.' }
    if ($LocalPort) { if ($LocalPort -lt 1 -or $LocalPort -gt 65535) { throw 'LocalPort must be 1..65535.' }; $pool.localPort = $LocalPort }
    if ($ProbeUrl) { $pool.probeUrl = $ProbeUrl }
    $resolvedSingBox = Get-ZtgSingBoxPath -Path $SingBoxPath
    $paths = Get-ZtgProxyRuntimePaths -DataRoot $DataRoot
    $occupied = Test-ZtgTcpPort -Address '127.0.0.1' -Port ([int]$pool.localPort) -TimeoutMilliseconds 200
    if ($occupied -and -not (Test-ZtgProxyRuntimeRunning -DataRoot $DataRoot)) { throw "127.0.0.1:$($pool.localPort) is occupied by a non-project process." }
    Write-ZtgInfo "Plan: enable current-user selector task; local entry 127.0.0.1:$($pool.localPort); sing-box=$resolvedSingBox"
    if (-not $Apply) { Write-ZtgWarn 'Preview only. Re-run with -Apply to register and start the selector.'; break }
    Assert-Administrator
    Set-DataDirectoryAcl -Root $data
    $runner = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot 'run-proxy-selector.ps1')).Path
    $poolLock = Enter-ZtgProxyPoolLock -DataRoot $DataRoot
    try {
      $pool = Get-ZtgProxyPool -DataRoot $DataRoot -Version $version
      if (@($pool.nodes | Where-Object { $_.enabled }).Count -eq 0) { throw 'Add at least one enabled node before Enable.' }
      if ($LocalPort) { $pool.localPort = $LocalPort }
      if ($ProbeUrl) { $pool.probeUrl = $ProbeUrl }
      $occupied = Test-ZtgTcpPort -Address '127.0.0.1' -Port ([int]$pool.localPort) -TimeoutMilliseconds 200
      if ($occupied -and -not (Test-ZtgProxyRuntimeRunning -DataRoot $DataRoot)) { throw "127.0.0.1:$($pool.localPort) is occupied by a non-project process." }
      $pool.enabled = $true
      $pool.lastAppliedVersion = $version
      Save-ZtgProxyPool -Pool $pool -DataRoot $DataRoot | Out-Null
    } finally {
      Exit-ZtgProxyPoolLock -LockHandle $poolLock
    }
    try {
      Register-ZtgProxySelectorTask -RunnerPath $runner -SingBoxPath $resolvedSingBox -DataRoot $DataRoot
      Enable-ScheduledTask -TaskName 'ProxySelector' -TaskPath '\ZeroTierGateway\' | Out-Null
      Start-ScheduledTask -TaskName 'ProxySelector' -TaskPath '\ZeroTierGateway\'
      $ready = $false
      for ($attempt = 0; $attempt -lt 60; $attempt++) {
        Start-Sleep -Milliseconds 500
        if (Test-ZtgTcpPort -Address '127.0.0.1' -Port ([int]$pool.localPort) -TimeoutMilliseconds 150) { $ready = $true; break }
      }
      if (-not $ready) { throw "Selector task started, but 127.0.0.1:$($pool.localPort) did not become ready within 30 seconds." }
    } catch {
      $enableError = $_
      Stop-ScheduledTask -TaskName 'ProxySelector' -TaskPath '\ZeroTierGateway\' -ErrorAction SilentlyContinue
      Disable-ScheduledTask -TaskName 'ProxySelector' -TaskPath '\ZeroTierGateway\' -ErrorAction SilentlyContinue | Out-Null
      try { Stop-ZtgProxyRuntime -DataRoot $DataRoot } catch { Write-ZtgWarn "Runtime cleanup needs manual review: $($_.Exception.Message)" }
      $poolLock = Enter-ZtgProxyPoolLock -DataRoot $DataRoot
      try {
        $rollbackPool = Get-ZtgProxyPool -DataRoot $DataRoot -Version $version
        $rollbackPool.enabled = $false
        Save-ZtgProxyPool -Pool $rollbackPool -DataRoot $DataRoot | Out-Null
      } finally {
        Exit-ZtgProxyPoolLock -LockHandle $poolLock
      }
      throw $enableError
    }
    Write-ZtgInfo "Enabled. Configure software to use 127.0.0.1:$($pool.localPort)."
    Write-ZtgInfo 'v2rayN: add one SOCKS node named ZeroTier 自动代理 with this address; keep old direct nodes for emergency fallback.'
  }
  'Disable' {
    Write-ZtgInfo 'Plan: stop selector task and project sing-box; keep the node list.'
    if (-not $Apply) { Write-ZtgWarn 'Preview only. Re-run with -Apply to disable.'; break }
    Assert-Administrator
    if (-not (Test-ZtgProxyTaskOwnership -ExpectedScript (Join-Path $PSScriptRoot 'run-proxy-selector.ps1'))) { throw 'Scheduled Task ownership check failed.' }
    $poolLock = Enter-ZtgProxyPoolLock -DataRoot $DataRoot
    try {
      Stop-ScheduledTask -TaskName 'ProxySelector' -TaskPath '\ZeroTierGateway\' -ErrorAction SilentlyContinue
      Disable-ScheduledTask -TaskName 'ProxySelector' -TaskPath '\ZeroTierGateway\' -ErrorAction SilentlyContinue | Out-Null
      Stop-ZtgProxyRuntime -DataRoot $DataRoot
      $pool = Get-ZtgProxyPool -DataRoot $DataRoot -Version $version
      $pool.enabled = $false
      $pool.selectedNode = $null
      Save-ZtgProxyPool -Pool $pool -DataRoot $DataRoot | Out-Null
    } finally {
      Exit-ZtgProxyPoolLock -LockHandle $poolLock
    }
    Write-ZtgInfo 'Disabled. Existing direct v2rayN nodes were not changed.'
  }
  'Remove' {
    if ($Name) {
      $candidate = Remove-ZtgProxyNode -Pool $pool -Name $Name
      Write-ZtgInfo "Plan: remove node $Name only."
      if (-not $Apply) { Write-ZtgWarn 'Preview only. Re-run with -Apply.'; break }
      Assert-Administrator
      Set-DataDirectoryAcl -Root $data
      $poolLock = Enter-ZtgProxyPoolLock -DataRoot $DataRoot
      try {
        $latestPool = Get-ZtgProxyPool -DataRoot $DataRoot -Version $version
        $candidate = Remove-ZtgProxyNode -Pool $latestPool -Name $Name
        Save-ZtgProxyPool -Pool $candidate -DataRoot $DataRoot | Out-Null
      } finally {
        Exit-ZtgProxyPoolLock -LockHandle $poolLock
      }
      Write-ZtgInfo "Node removed: $Name"
      break
    }
    Write-ZtgWarn 'Plan: stop and unregister the project selector, then remove proxy-pool runtime and state. Other project features and v2rayN are untouched.'
    if (-not $Apply) { Write-ZtgWarn 'Preview only. Add -Apply -ConfirmRemoval to remove the complete pool.'; break }
    if (-not $ConfirmRemoval) { throw 'Complete pool removal requires -ConfirmRemoval.' }
    Assert-Administrator
    if (-not (Test-ZtgProxyTaskOwnership -ExpectedScript (Join-Path $PSScriptRoot 'run-proxy-selector.ps1'))) { throw 'Scheduled Task ownership check failed.' }
    $poolLock = Enter-ZtgProxyPoolLock -DataRoot $DataRoot
    try {
      Stop-ScheduledTask -TaskName 'ProxySelector' -TaskPath '\ZeroTierGateway\' -ErrorAction SilentlyContinue
      Unregister-ScheduledTask -TaskName 'ProxySelector' -TaskPath '\ZeroTierGateway\' -Confirm:$false -ErrorAction SilentlyContinue
      Stop-ZtgProxyRuntime -DataRoot $DataRoot
      $paths = Get-ZtgProxyRuntimePaths -DataRoot $DataRoot
      if (Test-Path -LiteralPath $paths.Directory) { Remove-Item -LiteralPath $paths.Directory -Recurse -Force }
      $statePath = Get-ZtgStatePath -Name 'proxy-pool' -Root $DataRoot
      if (Test-Path -LiteralPath $statePath) { Remove-Item -LiteralPath $statePath -Force }
    } finally {
      Exit-ZtgProxyPoolLock -LockHandle $poolLock
    }
    Write-ZtgInfo 'Proxy pool removed. Existing direct nodes, firewall, PAC, and v2rayN configuration were not changed.'
  }
}
