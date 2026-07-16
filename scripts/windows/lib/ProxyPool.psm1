Set-StrictMode -Version Latest

Import-Module (Join-Path $PSScriptRoot 'Common.psm1') -Force
Import-Module (Join-Path $PSScriptRoot 'State.psm1') -Force

function Assert-ZtgProxyNodeInput {
  param(
    [Parameter(Mandatory)][string]$Name,
    [Parameter(Mandatory)][string]$ProxyHost,
    [Parameter(Mandatory)][int]$Port,
    [AllowEmptyString()][string]$Username = '',
    [AllowEmptyString()][string]$Password = ''
  )
  if ($Name -notmatch '^[A-Za-z0-9][A-Za-z0-9._-]{0,63}$') { throw "Invalid node name: $Name" }
  $parsed = $null
  $ipValid = [System.Net.IPAddress]::TryParse($ProxyHost, [ref]$parsed)
  $dnsValid = $ProxyHost -match '^(?=.{1,253}$)([A-Za-z0-9](?:[A-Za-z0-9-]{0,61}[A-Za-z0-9])?\.)*[A-Za-z0-9](?:[A-Za-z0-9-]{0,61}[A-Za-z0-9])?$'
  if (-not ($ipValid -or $dnsValid)) { throw "Invalid proxy host: $ProxyHost" }
  if ($Port -lt 1 -or $Port -gt 65535) { throw "Proxy port must be between 1 and 65535: $Port" }
  $hasUsername = -not [string]::IsNullOrWhiteSpace($Username)
  $hasPassword = -not [string]::IsNullOrWhiteSpace($Password)
  if ($hasUsername -xor $hasPassword) { throw 'Username and password must be both set or both empty.' }
  if ($Username -match '[\r\n]' -or $Password -match '[\r\n]') { throw 'Proxy credentials must be single-line values.' }
}

function New-ZtgProxyPool {
  param(
    [Parameter(Mandatory)][string]$Version,
    [int]$LocalPort = 20808,
    [string]$ProbeUrl = 'https://www.gstatic.com/generate_204'
  )
  if ($LocalPort -lt 1 -or $LocalPort -gt 65535) { throw 'Local proxy port must be between 1 and 65535.' }
  return [pscustomobject][ordered]@{
    schemaVersion = 1
    objectVersion = 1
    owner = 'zerotier-gateway'
    objectType = 'proxy-pool'
    objectName = 'default'
    enabled = $false
    lastAppliedVersion = $Version
    generation = 1
    localPort = $LocalPort
    probeUrl = $ProbeUrl
    intervalSeconds = 10
    timeoutSeconds = 5
    failureThreshold = 2
    recoveryThreshold = 3
    holdDownSeconds = 60
    selectedNode = $null
    lastSwitchAt = $null
    updatedAt = [DateTime]::UtcNow.ToString('o')
    nodes = @()
  }
}

function Get-ZtgProxyPool {
  param(
    [string]$DataRoot,
    [string]$Version = 'unknown'
  )
  $pool = Read-ZtgJsonState -Name 'proxy-pool' -Root $DataRoot -ExpectedObjectType 'proxy-pool' -ExpectedObjectName 'default'
  if ($null -eq $pool) { return (New-ZtgProxyPool -Version $Version) }
  return $pool
}

function Save-ZtgProxyPool {
  param(
    [Parameter(Mandatory)]$Pool,
    [string]$DataRoot
  )
  $Pool.updatedAt = [DateTime]::UtcNow.ToString('o')
  Write-ZtgJsonState -Name 'proxy-pool' -Value $Pool -Root $DataRoot
}

function Enter-ZtgProxyPoolLock {
  param(
    [string]$DataRoot,
    [ValidateRange(1,300)][int]$TimeoutSeconds = 60
  )
  $lockDirectory = Join-Path (Get-ZtgDataRoot -Root $DataRoot) 'locks'
  [IO.Directory]::CreateDirectory($lockDirectory) | Out-Null
  $lockPath = Join-Path $lockDirectory 'proxy-pool.lock'
  $deadline = [DateTime]::UtcNow.AddSeconds($TimeoutSeconds)
  do {
    try {
      return [IO.File]::Open($lockPath, [IO.FileMode]::OpenOrCreate, [IO.FileAccess]::ReadWrite, [IO.FileShare]::None)
    } catch [IO.IOException] {
      if ([DateTime]::UtcNow -ge $deadline) {
        throw "Timed out waiting for the proxy-pool operation lock: $lockPath"
      }
      Start-Sleep -Milliseconds 100
    }
  } while ($true)
}

function Exit-ZtgProxyPoolLock {
  param($LockHandle)
  if ($null -ne $LockHandle) { $LockHandle.Dispose() }
}

function Add-ZtgProxyNode {
  param(
    [Parameter(Mandatory)]$Pool,
    [Parameter(Mandatory)][string]$Name,
    [Parameter(Mandatory)][string]$Server,
    [Parameter(Mandatory)][int]$Port,
    [AllowEmptyString()][string]$Username = '',
    [AllowEmptyString()][string]$Password = '',
    [bool]$Enabled = $true
  )
  Assert-ZtgProxyNodeInput -Name $Name -ProxyHost $Server -Port $Port -Username $Username -Password $Password
  if (@($Pool.nodes | Where-Object { $_.name -eq $Name }).Count -gt 0) { throw "Proxy node already exists: $Name" }
  if (@($Pool.nodes).Count -ge 16) { throw 'A proxy pool supports at most 16 nodes.' }
  $node = [pscustomobject][ordered]@{
    name = $Name
    host = $Server
    port = $Port
    username = $Username
    password = $Password
    enabled = $Enabled
    healthState = $(if ($Enabled) { 'unknown' } else { 'disabled' })
    consecutiveSuccesses = 0
    consecutiveFailures = 0
    lastLatencyMs = $null
    lastCheckedAt = $null
    lastError = $null
  }
  $Pool.nodes = @($Pool.nodes) + @($node)
  $Pool.generation = [int]$Pool.generation + 1
  return $Pool
}

function Update-ZtgProxyNode {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)]$Pool,
    [Parameter(Mandatory)][string]$Name,
    [string]$Server,
    [int]$Port,
    [AllowNull()][string]$Username,
    [AllowNull()][string]$Password,
    [AllowNull()][Nullable[bool]]$Enabled
  )
  $node = @($Pool.nodes | Where-Object { $_.name -eq $Name } | Select-Object -First 1)
  if ($node.Count -eq 0) { throw "Proxy node not found: $Name" }
  $target = $node[0]
  $newHost = if ($PSBoundParameters.ContainsKey('Server')) { $Server } else { [string]$target.host }
  $newPort = if ($PSBoundParameters.ContainsKey('Port')) { $Port } else { [int]$target.port }
  $newUsername = if ($PSBoundParameters.ContainsKey('Username')) { [string]$Username } else { [string]$target.username }
  $newPassword = if ($PSBoundParameters.ContainsKey('Password')) { [string]$Password } else { [string]$target.password }
  Assert-ZtgProxyNodeInput -Name $Name -ProxyHost $newHost -Port $newPort -Username $newUsername -Password $newPassword
  $target.host = $newHost
  $target.port = $newPort
  $target.username = $newUsername
  $target.password = $newPassword
  if ($PSBoundParameters.ContainsKey('Enabled')) {
    $target.enabled = [bool]$Enabled
    $target.healthState = if ($target.enabled) { 'unknown' } else { 'disabled' }
    $target.consecutiveSuccesses = 0
    $target.consecutiveFailures = 0
  }
  $Pool.generation = [int]$Pool.generation + 1
  return $Pool
}

function Remove-ZtgProxyNode {
  param(
    [Parameter(Mandatory)]$Pool,
    [Parameter(Mandatory)][string]$Name
  )
  $before = @($Pool.nodes).Count
  $Pool.nodes = @($Pool.nodes | Where-Object { $_.name -ne $Name })
  if (@($Pool.nodes).Count -eq $before) { throw "Proxy node not found: $Name" }
  if ([string]$Pool.selectedNode -eq $Name) { $Pool.selectedNode = $null }
  $Pool.generation = [int]$Pool.generation + 1
  return $Pool
}

function Update-ZtgProxyNodeHealth {
  param(
    [Parameter(Mandatory)]$Node,
    [Parameter(Mandatory)][bool]$Success,
    [AllowNull()][Nullable[int]]$LatencyMs,
    [AllowEmptyString()][string]$ErrorMessage = '',
    [int]$FailureThreshold = 2,
    [int]$RecoveryThreshold = 3
  )
  if (-not [bool]$Node.enabled) {
    $Node.healthState = 'disabled'
    return $Node
  }
  $Node.lastCheckedAt = [DateTime]::UtcNow.ToString('o')
  if ($Success) {
    $Node.consecutiveSuccesses = [int]$Node.consecutiveSuccesses + 1
    $Node.consecutiveFailures = 0
    $Node.lastLatencyMs = $LatencyMs
    $Node.lastError = $null
    if ([int]$Node.consecutiveSuccesses -ge $RecoveryThreshold) { $Node.healthState = 'healthy' }
  } else {
    $Node.consecutiveFailures = [int]$Node.consecutiveFailures + 1
    $Node.consecutiveSuccesses = 0
    $Node.lastError = $ErrorMessage
    if ([int]$Node.consecutiveFailures -ge $FailureThreshold) { $Node.healthState = 'unhealthy' }
  }
  return $Node
}

function Select-ZtgProxyNode {
  param([Parameter(Mandatory)]$Pool)
  $previous = [string]$Pool.selectedNode
  $current = @($Pool.nodes | Where-Object { $_.name -eq $previous -and $_.enabled -and $_.healthState -eq 'healthy' } | Select-Object -First 1)
  $selected = $null
  if ($current.Count -gt 0) {
    $selected = $current[0]
  } else {
    $candidates = @($Pool.nodes | Where-Object { $_.enabled -and $_.healthState -eq 'healthy' } | Sort-Object @{ Expression = { if ($null -eq $_.lastLatencyMs) { [int]::MaxValue } else { [int]$_.lastLatencyMs } } }, name)
    if ($candidates.Count -gt 0) { $selected = $candidates[0] }
  }
  $newName = if ($null -eq $selected) { $null } else { [string]$selected.name }
  $changed = ([string]$previous -ne [string]$newName)
  if ($changed) {
    $Pool.selectedNode = $newName
    $Pool.lastSwitchAt = [DateTime]::UtcNow.ToString('o')
    $Pool.generation = [int]$Pool.generation + 1
  }
  return [pscustomobject]@{ Pool = $Pool; SelectedNode = $selected; Changed = $changed }
}

function New-ZtgSingBoxProxyConfig {
  param(
    [Parameter(Mandatory)]$Pool,
    [AllowNull()]$SelectedNode
  )
  $outbound = $null
  if ($null -eq $SelectedNode) {
    $outbound = [ordered]@{ type = 'block'; tag = 'proxy-unavailable' }
    $finalTag = 'proxy-unavailable'
  } else {
    $outbound = [ordered]@{
      type = 'socks'
      tag = 'selected-proxy'
      server = [string]$SelectedNode.host
      server_port = [int]$SelectedNode.port
      version = '5'
    }
    if (-not [string]::IsNullOrWhiteSpace([string]$SelectedNode.username)) {
      $outbound.username = [string]$SelectedNode.username
      $outbound.password = [string]$SelectedNode.password
    }
    $finalTag = 'selected-proxy'
  }
  $config = [ordered]@{
    log = [ordered]@{ level = 'info'; timestamp = $true }
    inbounds = @([ordered]@{ type = 'mixed'; tag = 'local-mixed'; listen = '127.0.0.1'; listen_port = [int]$Pool.localPort })
    outbounds = @($outbound)
    route = [ordered]@{ final = $finalTag }
  }
  return (($config | ConvertTo-Json -Depth 10) + [Environment]::NewLine)
}

function Get-ZtgSingBoxPath {
  param([string]$Path)
  if ($Path) {
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { throw "sing-box executable not found: $Path" }
    return (Resolve-Path -LiteralPath $Path).Path
  }
  $command = Get-Command sing-box.exe -ErrorAction SilentlyContinue
  if (-not $command) { $command = Get-Command sing-box -ErrorAction SilentlyContinue }
  if (-not $command) { throw 'sing-box was not found. Install it first, then retry Enable with -SingBoxPath if needed.' }
  return $command.Source
}

function New-ZtgCurlArguments {
  param(
    [Parameter(Mandatory)]$Node,
    [Parameter(Mandatory)][string]$Url,
    [int]$TimeoutSeconds = 5
  )
  $proxyHost = [string]$Node.host
  $parsedAddress = $null
  if ([Net.IPAddress]::TryParse($proxyHost, [ref]$parsedAddress) -and $parsedAddress.AddressFamily -eq [Net.Sockets.AddressFamily]::InterNetworkV6) {
    $proxyHost = "[$proxyHost]"
  }
  $arguments = @('--silent','--show-error','--fail','--ssl-no-revoke','--max-time',[string]$TimeoutSeconds,'--socks5-hostname',("{0}:{1}" -f $proxyHost,$Node.port),'--output','NUL')
  if (-not [string]::IsNullOrWhiteSpace([string]$Node.username)) {
    $arguments += @('--proxy-user',("{0}:{1}" -f $Node.username,$Node.password))
  }
  $arguments += $Url
  return [string[]]$arguments
}

function Test-ZtgProxyNode {
  param(
    [Parameter(Mandatory)]$Node,
    [Parameter(Mandatory)][string]$Url,
    [int]$TimeoutSeconds = 5
  )
  $curl = Get-Command curl.exe -ErrorAction SilentlyContinue
  if (-not $curl) { throw 'curl.exe is required for real SOCKS health checks.' }
  $arguments = New-ZtgCurlArguments -Node $Node -Url $Url -TimeoutSeconds $TimeoutSeconds
  $watch = [Diagnostics.Stopwatch]::StartNew()
  try {
    & $curl.Source @arguments 2>&1 | Out-Null
    $exitCode = $LASTEXITCODE
    $watch.Stop()
    return [pscustomobject]@{ Name = $Node.name; Success = ($exitCode -eq 0); LatencyMs = [int]$watch.ElapsedMilliseconds; Error = $(if ($exitCode -eq 0) { $null } else { "curl exit $exitCode" }) }
  } catch {
    $watch.Stop()
    return [pscustomobject]@{ Name = $Node.name; Success = $false; LatencyMs = [int]$watch.ElapsedMilliseconds; Error = $_.Exception.Message }
  }
}

function Invoke-ZtgProxyHealthBatch {
  param(
    [Parameter(Mandatory)][object[]]$Nodes,
    [Parameter(Mandatory)][string]$Url,
    [int]$TimeoutSeconds = 5,
    [int]$MaxConcurrency = 4
  )
  $curl = Get-Command curl.exe -ErrorAction SilentlyContinue
  if (-not $curl) { throw 'curl.exe is required for real SOCKS health checks.' }
  $enabled = @($Nodes | Where-Object { $_.enabled })
  if ($enabled.Count -eq 0) { return @() }
  $pool = [RunspaceFactory]::CreateRunspacePool(1, [Math]::Max(1, [Math]::Min($MaxConcurrency, 4)))
  $pool.Open()
  $jobs = @()
  $probe = {
    param($CurlPath, $CurlArguments, $NodeName)
    $watch = [Diagnostics.Stopwatch]::StartNew()
    try {
      & $CurlPath @CurlArguments 2>&1 | Out-Null
      $code = $LASTEXITCODE
      $watch.Stop()
      [pscustomobject]@{ Name = $NodeName; Success = ($code -eq 0); LatencyMs = [int]$watch.ElapsedMilliseconds; Error = $(if ($code -eq 0) { $null } else { "curl exit $code" }) }
    } catch {
      $watch.Stop()
      [pscustomobject]@{ Name = $NodeName; Success = $false; LatencyMs = [int]$watch.ElapsedMilliseconds; Error = $_.Exception.Message }
    }
  }
  try {
    foreach ($node in $enabled) {
      $arguments = New-ZtgCurlArguments -Node $node -Url $Url -TimeoutSeconds $TimeoutSeconds
      $powerShell = [PowerShell]::Create()
      $powerShell.RunspacePool = $pool
      $powerShell.AddScript($probe).AddArgument($curl.Source).AddArgument([object]$arguments).AddArgument([string]$node.name) | Out-Null
      $jobs += [pscustomobject]@{ PowerShell = $powerShell; Async = $powerShell.BeginInvoke() }
    }
    $results = @()
    foreach ($job in $jobs) { $results += @($job.PowerShell.EndInvoke($job.Async)) }
    return $results
  } finally {
    foreach ($job in $jobs) { $job.PowerShell.Dispose() }
    $pool.Close()
    $pool.Dispose()
  }
}

function Test-ZtgTcpPort {
  param(
    [Parameter(Mandatory)][string]$Address,
    [Parameter(Mandatory)][int]$Port,
    [int]$TimeoutMilliseconds = 2000
  )
  $client = New-Object Net.Sockets.TcpClient
  try {
    $async = $client.BeginConnect($Address, $Port, $null, $null)
    if (-not $async.AsyncWaitHandle.WaitOne($TimeoutMilliseconds, $false)) { return $false }
    $client.EndConnect($async)
    return $true
  } catch { return $false } finally { $client.Dispose() }
}

function Get-ZtgProxyRuntimePaths {
  param([string]$DataRoot)
  $runtime = Join-Path (Get-ZtgDataRoot -Root $DataRoot) 'runtime'
  return [pscustomobject]@{
    Directory = $runtime
    Config = Join-Path $runtime 'proxy-selector.json'
    Candidate = Join-Path $runtime 'proxy-selector.candidate.json'
    Backup = Join-Path $runtime 'proxy-selector.last-good.json'
    Pid = Join-Path $runtime 'sing-box.pid.json'
    Stdout = Join-Path $runtime 'sing-box.stdout.log'
    Stderr = Join-Path $runtime 'sing-box.stderr.log'
  }
}

function Test-ZtgProxyRuntimeConfigCurrent {
  param(
    [Parameter(Mandatory)]$Pool,
    [AllowNull()]$SelectedNode,
    [string]$DataRoot
  )
  $paths = Get-ZtgProxyRuntimePaths -DataRoot $DataRoot
  if (-not (Test-Path -LiteralPath $paths.Config -PathType Leaf)) { return $false }
  $expected = New-ZtgSingBoxProxyConfig -Pool $Pool -SelectedNode $SelectedNode
  $actual = [IO.File]::ReadAllText($paths.Config)
  return ($actual -eq $expected)
}

function Test-ZtgProxyRuntimeRunning {
  param([string]$DataRoot)
  $paths = Get-ZtgProxyRuntimePaths -DataRoot $DataRoot
  if (-not (Test-Path -LiteralPath $paths.Pid -PathType Leaf)) { return $false }
  try {
    $record = Get-Content -LiteralPath $paths.Pid -Raw | ConvertFrom-Json
    $process = Get-Process -Id ([int]$record.pid) -ErrorAction Stop
    $actualPath = $process.Path
    if (-not $actualPath) { return $false }
    if ([IO.Path]::GetFullPath($actualPath) -ne [IO.Path]::GetFullPath([string]$record.executable)) { return $false }
    if ($record.PSObject.Properties.Name -contains 'processStartTimeUtc') {
      return ([DateTime]::Parse($process.StartTime.ToUniversalTime().ToString('o')) -eq [DateTime]::Parse([string]$record.processStartTimeUtc))
    }
    return $true
  } catch {
    return $false
  }
}

function Test-ZtgProxyRuntimeLogBudget {
  param(
    [string]$DataRoot,
    [long]$MaxBytes = 5MB
  )
  $paths = Get-ZtgProxyRuntimePaths -DataRoot $DataRoot
  foreach ($path in @($paths.Stdout,$paths.Stderr)) {
    if ((Test-Path -LiteralPath $path -PathType Leaf) -and (Get-Item -LiteralPath $path).Length -ge $MaxBytes) { return $false }
  }
  return $true
}

function Rotate-ZtgProxyRuntimeLogs {
  param(
    [string]$DataRoot,
    [long]$MaxBytes = 5MB
  )
  $paths = Get-ZtgProxyRuntimePaths -DataRoot $DataRoot
  foreach ($path in @($paths.Stdout,$paths.Stderr)) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { continue }
    if ((Get-Item -LiteralPath $path).Length -lt $MaxBytes) { continue }
    $backup = "$path.1"
    Remove-Item -LiteralPath $backup -Force -ErrorAction SilentlyContinue
    Move-Item -LiteralPath $path -Destination $backup -Force
  }
}

function Stop-ZtgProxyRuntime {
  param([string]$DataRoot)
  $paths = Get-ZtgProxyRuntimePaths -DataRoot $DataRoot
  if (-not (Test-Path -LiteralPath $paths.Pid)) { return }
  $record = Get-Content -LiteralPath $paths.Pid -Raw | ConvertFrom-Json
  $process = Get-Process -Id ([int]$record.pid) -ErrorAction SilentlyContinue
  if ($process) {
    $actualPath = $null
    try { $actualPath = $process.Path } catch { }
    if (-not $actualPath) {
      throw "PID $($record.pid) exists, but its executable could not be verified. It was not stopped."
    }
    if ([System.IO.Path]::GetFullPath($actualPath) -ne [System.IO.Path]::GetFullPath([string]$record.executable)) {
      throw "PID $($record.pid) is no longer the project sing-box process. It was not stopped."
    }
    if ($record.PSObject.Properties.Name -contains 'processStartTimeUtc') {
      $actualStart = $process.StartTime.ToUniversalTime().ToString('o')
      if ([DateTime]::Parse($actualStart) -ne [DateTime]::Parse([string]$record.processStartTimeUtc)) {
        throw "PID $($record.pid) was reused by another process. It was not stopped."
      }
    }
    Stop-Process -Id $process.Id -Force -ErrorAction Stop
    $process.WaitForExit(5000) | Out-Null
  }
  Remove-Item -LiteralPath $paths.Pid -Force -ErrorAction SilentlyContinue
}

function Start-ZtgProxyRuntime {
  param(
    [Parameter(Mandatory)][string]$SingBoxPath,
    [Parameter(Mandatory)][string]$ConfigPath,
    [string]$DataRoot
  )
  $paths = Get-ZtgProxyRuntimePaths -DataRoot $DataRoot
  Rotate-ZtgProxyRuntimeLogs -DataRoot $DataRoot
  $process = Start-Process -FilePath $SingBoxPath -ArgumentList @('run','-c',$ConfigPath) -PassThru -WindowStyle Hidden -RedirectStandardOutput $paths.Stdout -RedirectStandardError $paths.Stderr
  try {
    $record = [ordered]@{
      pid = $process.Id
      executable = $SingBoxPath
      config = $ConfigPath
      processStartTimeUtc = $process.StartTime.ToUniversalTime().ToString('o')
      startedAt = [DateTime]::UtcNow.ToString('o')
    }
    $record | ConvertTo-Json | Set-Content -LiteralPath $paths.Pid -Encoding UTF8
    return $process
  } catch {
    if ($process -and -not $process.HasExited) {
      Stop-Process -Id $process.Id -Force -ErrorAction SilentlyContinue
      $process.WaitForExit(5000) | Out-Null
    }
    throw
  }
}

function Apply-ZtgProxyRuntime {
  param(
    [Parameter(Mandatory)]$Pool,
    [AllowNull()]$SelectedNode,
    [Parameter(Mandatory)][string]$SingBoxPath,
    [string]$DataRoot
  )
  $paths = Get-ZtgProxyRuntimePaths -DataRoot $DataRoot
  [System.IO.Directory]::CreateDirectory($paths.Directory) | Out-Null
  $config = New-ZtgSingBoxProxyConfig -Pool $Pool -SelectedNode $SelectedNode
  $utf8NoBom = New-Object Text.UTF8Encoding($false)
  [IO.File]::WriteAllText($paths.Candidate, $config, $utf8NoBom)
  & $SingBoxPath check -c $paths.Candidate
  if ($LASTEXITCODE -ne 0) { throw 'sing-box rejected the candidate proxy selector config.' }
  $hadConfig = Test-Path -LiteralPath $paths.Config
  if ($hadConfig) { Copy-Item -LiteralPath $paths.Config -Destination $paths.Backup -Force }
  try {
    Stop-ZtgProxyRuntime -DataRoot $DataRoot
    Move-Item -LiteralPath $paths.Candidate -Destination $paths.Config -Force
    $process = Start-ZtgProxyRuntime -SingBoxPath $SingBoxPath -ConfigPath $paths.Config -DataRoot $DataRoot
    $ready = $false
    for ($attempt = 0; $attempt -lt 20; $attempt++) {
      Start-Sleep -Milliseconds 250
      if ($process.HasExited) { break }
      if (Test-ZtgTcpPort -Address '127.0.0.1' -Port ([int]$Pool.localPort) -TimeoutMilliseconds 100) { $ready = $true; break }
    }
    if (-not $ready) { throw "Local proxy did not listen on 127.0.0.1:$($Pool.localPort)." }
  } catch {
    Stop-ZtgProxyRuntime -DataRoot $DataRoot
    if ($hadConfig -and (Test-Path -LiteralPath $paths.Backup)) {
      Copy-Item -LiteralPath $paths.Backup -Destination $paths.Config -Force
      Start-ZtgProxyRuntime -SingBoxPath $SingBoxPath -ConfigPath $paths.Config -DataRoot $DataRoot | Out-Null
    }
    throw
  } finally {
    Remove-Item -LiteralPath $paths.Candidate -Force -ErrorAction SilentlyContinue
  }
}

function Test-ZtgProxyTaskOwnership {
  param([string]$ExpectedScript)
  $task = Get-ScheduledTask -TaskName 'ProxySelector' -TaskPath '\ZeroTierGateway\' -ErrorAction SilentlyContinue
  if (-not $task) { return $true }
  if ($task.PSObject.Properties.Name -notcontains 'Actions' -or $task.PSObject.Properties.Name -notcontains 'Principal') { return $false }
  $actions = @($task.Actions)
  if ($actions.Count -ne 1) { return $false }
  $action = $actions[0]
  if ($action.PSObject.Properties.Name -notcontains 'Execute' -or $action.PSObject.Properties.Name -notcontains 'Arguments') { return $false }
  $principal = $task.Principal
  if ($null -eq $principal) { return $false }
  foreach ($property in @('UserId','LogonType','RunLevel')) {
    if ($principal.PSObject.Properties.Name -notcontains $property) { return $false }
  }
  try {
    $expectedPowerShell = [IO.Path]::GetFullPath((Join-Path $PSHOME 'powershell.exe'))
    $actualPowerShell = [IO.Path]::GetFullPath([string]$action.Execute)
    if (-not [StringComparer]::OrdinalIgnoreCase.Equals($actualPowerShell, $expectedPowerShell)) { return $false }
    $fileMatches = [regex]::Matches([string]$action.Arguments, '(?i)(?:^|\s)-File\s+(?:"([^"]+)"|''([^'']+)''|(\S+))')
    if ($fileMatches.Count -ne 1) { return $false }
    $runner = @($fileMatches[0].Groups[1].Value, $fileMatches[0].Groups[2].Value, $fileMatches[0].Groups[3].Value | Where-Object { $_ })[0]
    $actualRunner = [IO.Path]::GetFullPath($runner)
    $expectedRunner = [IO.Path]::GetFullPath($ExpectedScript)
    if (-not [StringComparer]::OrdinalIgnoreCase.Equals($actualRunner, $expectedRunner)) { return $false }
    $currentUser = [Security.Principal.WindowsIdentity]::GetCurrent().Name
    return (
      [StringComparer]::OrdinalIgnoreCase.Equals([string]$principal.UserId, $currentUser) -and
      [string]$principal.LogonType -eq 'Interactive' -and
      [string]$principal.RunLevel -eq 'Limited'
    )
  } catch {
    return $false
  }
}

function Register-ZtgProxySelectorTask {
  param(
    [Parameter(Mandatory)][string]$RunnerPath,
    [Parameter(Mandatory)][string]$SingBoxPath,
    [string]$DataRoot
  )
  if (-not (Test-ZtgProxyTaskOwnership -ExpectedScript $RunnerPath)) { throw 'Scheduled Task name is owned by another command. Nothing was changed.' }
  $powerShellPath = Join-Path $PSHOME 'powershell.exe'
  $arguments = "-NoLogo -NoProfile -ExecutionPolicy Bypass -File `"$RunnerPath`" -SingBoxPath `"$SingBoxPath`""
  if ($DataRoot) { $arguments += " -DataRoot `"$DataRoot`"" }
  $user = [Security.Principal.WindowsIdentity]::GetCurrent().Name
  $action = New-ScheduledTaskAction -Execute $powerShellPath -Argument $arguments
  $trigger = New-ScheduledTaskTrigger -AtLogOn -User $user
  $principal = New-ScheduledTaskPrincipal -UserId $user -LogonType Interactive -RunLevel Limited
  $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -RestartCount 3 -RestartInterval (New-TimeSpan -Minutes 1) -ExecutionTimeLimit ([TimeSpan]::Zero)
  Register-ScheduledTask -TaskName 'ProxySelector' -TaskPath '\ZeroTierGateway\' -Action $action -Trigger $trigger -Principal $principal -Settings $settings -Force | Out-Null
}

Export-ModuleMember -Function Assert-ZtgProxyNodeInput,New-ZtgProxyPool,Get-ZtgProxyPool,Save-ZtgProxyPool,Enter-ZtgProxyPoolLock,Exit-ZtgProxyPoolLock,Add-ZtgProxyNode,Update-ZtgProxyNode,Remove-ZtgProxyNode,Update-ZtgProxyNodeHealth,Select-ZtgProxyNode,New-ZtgSingBoxProxyConfig,Get-ZtgSingBoxPath,New-ZtgCurlArguments,Test-ZtgProxyNode,Invoke-ZtgProxyHealthBatch,Test-ZtgTcpPort,Get-ZtgProxyRuntimePaths,Test-ZtgProxyRuntimeConfigCurrent,Test-ZtgProxyRuntimeRunning,Test-ZtgProxyRuntimeLogBudget,Rotate-ZtgProxyRuntimeLogs,Stop-ZtgProxyRuntime,Start-ZtgProxyRuntime,Apply-ZtgProxyRuntime,Test-ZtgProxyTaskOwnership,Register-ZtgProxySelectorTask
