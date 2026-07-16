$ErrorActionPreference = 'Stop'
$root = Resolve-Path (Join-Path $PSScriptRoot '..\..')
Import-Module (Join-Path $root 'scripts\windows\lib\ProxyPool.psm1') -Force

function Assert-True { param([bool]$Value,[string]$Message) if (-not $Value) { throw $Message } }
function Assert-Equal { param($Actual,$Expected,[string]$Message) if ([string]$Actual -ne [string]$Expected) { throw "$Message Expected=$Expected Actual=$Actual" } }

$pool = New-ZtgProxyPool -Version '1.4.0-dev'
$pool = Add-ZtgProxyNode -Pool $pool -Name 'old-gold' -Server '10.246.77.1' -Port 10808 -Username '' -Password ''
$pool = Add-ZtgProxyNode -Pool $pool -Name 'tokyo' -Server '10.246.77.3' -Port 10808 -Username 'u' -Password 'p'
Assert-Equal @($pool.nodes).Count 2 'Two nodes should be saved.'
$configuredFailoverBudget = ([int]$pool.failureThreshold * [int]$pool.intervalSeconds) + [int]$pool.timeoutSeconds + 5
Assert-True ($configuredFailoverBudget -le 60) 'Configured failure detection and local runtime apply budget must remain within 60 seconds.'

$duplicateRejected = $false
try { Add-ZtgProxyNode -Pool $pool -Name 'tokyo' -Server '10.246.77.3' -Port 10808 | Out-Null } catch { $duplicateRejected = $true }
Assert-True $duplicateRejected 'Duplicate node name should be rejected.'

$fullPool = New-ZtgProxyPool -Version '1.4.0-dev'
1..16 | ForEach-Object { $fullPool = Add-ZtgProxyNode -Pool $fullPool -Name "node-$_" -Server "10.0.0.$_" -Port 1080 }
$capacityRejected = $false
try { Add-ZtgProxyNode -Pool $fullPool -Name 'node-17' -Server '10.0.0.17' -Port 1080 | Out-Null } catch { $capacityRejected = $true }
Assert-True $capacityRejected 'A seventeenth node should be rejected.'

foreach ($node in $pool.nodes) {
  1..3 | ForEach-Object {
    $latency = if ($node.name -eq 'old-gold') { 160 } else { 100 }
    Update-ZtgProxyNodeHealth -Node $node -Success $true -LatencyMs $latency | Out-Null
  }
}
$selection = Select-ZtgProxyNode -Pool $pool
$pool = $selection.Pool
Assert-Equal $pool.selectedNode 'tokyo' 'Lowest-latency healthy node should be selected initially.'

$tokyo = $pool.nodes | Where-Object name -eq 'tokyo'
Update-ZtgProxyNodeHealth -Node $tokyo -Success $false -ErrorMessage 'down' | Out-Null
Assert-Equal $tokyo.healthState 'healthy' 'One failure must not switch a healthy node.'
Update-ZtgProxyNodeHealth -Node $tokyo -Success $false -ErrorMessage 'down' | Out-Null
Assert-Equal $tokyo.healthState 'unhealthy' 'Two failures should mark the node unhealthy.'
$selection = Select-ZtgProxyNode -Pool $pool
$pool = $selection.Pool
Assert-Equal $pool.selectedNode 'old-gold' 'Current unhealthy node should switch immediately despite hold-down.'

1..3 | ForEach-Object { Update-ZtgProxyNodeHealth -Node $tokyo -Success $true -LatencyMs 90 | Out-Null }
$selection = Select-ZtgProxyNode -Pool $pool
$pool = $selection.Pool
Assert-Equal $pool.selectedNode 'old-gold' 'A recovered faster node must not preempt the current healthy node during anti-flap hold.'
1..2 | ForEach-Object { Update-ZtgProxyNodeHealth -Node $tokyo -Success $false -ErrorMessage 'down again' | Out-Null }

$oldGold = $pool.nodes | Where-Object name -eq 'old-gold'
1..2 | ForEach-Object { Update-ZtgProxyNodeHealth -Node $oldGold -Success $false -ErrorMessage 'down' | Out-Null }
$selection = Select-ZtgProxyNode -Pool $pool
Assert-True ($null -eq $selection.SelectedNode) 'All nodes down should select no upstream.'
$blockedConfig = New-ZtgSingBoxProxyConfig -Pool $selection.Pool -SelectedNode $null
$blocked = $blockedConfig | ConvertFrom-Json
Assert-Equal $blocked.outbounds[0].type 'block' 'All-down config must fail closed.'
Assert-True (-not ($blockedConfig -match '"type"\s*:\s*"direct"')) 'All-down config must not contain a direct outbound.'

1..3 | ForEach-Object { Update-ZtgProxyNodeHealth -Node $tokyo -Success $true -LatencyMs 90 | Out-Null }
$selection = Select-ZtgProxyNode -Pool $selection.Pool
$selectedConfig = New-ZtgSingBoxProxyConfig -Pool $selection.Pool -SelectedNode $selection.SelectedNode
$selected = $selectedConfig | ConvertFrom-Json
Assert-Equal $selected.outbounds[0].server '10.246.77.3' 'Recovered upstream should be rendered.'
Assert-Equal $selected.outbounds[0].username 'u' 'Optional authentication should be rendered.'

$invalidRejected = $false
try { Assert-ZtgProxyNodeInput -Name '..\bad' -ProxyHost '10.0.0.1' -Port 1080 } catch { $invalidRejected = $true }
Assert-True $invalidRejected 'Path-like names should be rejected.'
$ipv6Node = [pscustomobject]@{ name='ipv6'; host='2001:db8::1'; port=1080; username=''; password='' }
$ipv6Arguments = New-ZtgCurlArguments -Node $ipv6Node -Url 'https://example.com' -TimeoutSeconds 5
Assert-True ($ipv6Arguments -contains '[2001:db8::1]:1080') 'IPv6 SOCKS endpoint must be bracketed for curl.'
Assert-True ($ipv6Arguments -contains '--ssl-no-revoke') 'Windows proxy probes must tolerate unavailable certificate-revocation endpoints.'

function New-MockSelectorTask {
  param(
    [string]$Execute,
    [string]$Arguments,
    [string]$UserId,
    [string]$LogonType = 'Interactive',
    [string]$RunLevel = 'Limited'
  )
  [pscustomobject]@{
    Actions = @([pscustomobject]@{ Execute = $Execute; Arguments = $Arguments })
    Principal = [pscustomobject]@{ UserId = $UserId; LogonType = $LogonType; RunLevel = $RunLevel }
  }
}

$expectedRunner = (Resolve-Path -LiteralPath (Join-Path $root 'scripts\windows\run-proxy-selector.ps1')).Path
$expectedPowerShell = Join-Path $PSHOME 'powershell.exe'
$currentUser = [Security.Principal.WindowsIdentity]::GetCurrent().Name
$global:ZtgMockScheduledTask = New-MockSelectorTask -Execute $expectedPowerShell -Arguments "-NoProfile -File `"$expectedRunner`"" -UserId $currentUser
function global:Get-ScheduledTask { $global:ZtgMockScheduledTask }
try {
  Assert-True (Test-ZtgProxyTaskOwnership -ExpectedScript $expectedRunner) 'Correct selector Task identity was rejected.'
  $global:ZtgMockScheduledTask = New-MockSelectorTask -Execute 'C:\Windows\System32\cmd.exe' -Arguments "/c echo $expectedRunner" -UserId $currentUser
  Assert-True (-not (Test-ZtgProxyTaskOwnership -ExpectedScript $expectedRunner)) 'Foreign Task executable was accepted.'
  $global:ZtgMockScheduledTask = New-MockSelectorTask -Execute $expectedPowerShell -Arguments "-File `"$expectedRunner`"" -UserId 'FOREIGN\User'
  Assert-True (-not (Test-ZtgProxyTaskOwnership -ExpectedScript $expectedRunner)) 'Foreign Task principal was accepted.'
  $global:ZtgMockScheduledTask = New-MockSelectorTask -Execute $expectedPowerShell -Arguments "-File `"$expectedRunner`"" -UserId $currentUser -RunLevel 'Highest'
  Assert-True (-not (Test-ZtgProxyTaskOwnership -ExpectedScript $expectedRunner)) 'Elevated Task principal was accepted.'
  $global:ZtgMockScheduledTask = New-MockSelectorTask -Execute $expectedPowerShell -Arguments "-File `"$expectedRunner`" -File `"$expectedRunner`"" -UserId $currentUser
  Assert-True (-not (Test-ZtgProxyTaskOwnership -ExpectedScript $expectedRunner)) 'Task with duplicate -File arguments was accepted.'
} finally {
  Remove-Item Function:\Get-ScheduledTask -ErrorAction SilentlyContinue
  Remove-Variable ZtgMockScheduledTask -Scope Global -ErrorAction SilentlyContinue
}

$temp = Join-Path ([IO.Path]::GetTempPath()) ('ztg-pool-test-' + [guid]::NewGuid().ToString('N'))
try {
  Save-ZtgProxyPool -Pool $selection.Pool -DataRoot $temp | Out-Null
  $firstLock = Enter-ZtgProxyPoolLock -DataRoot $temp
  try {
    $contentionRejected = $false
    try { Enter-ZtgProxyPoolLock -DataRoot $temp -TimeoutSeconds 1 | Out-Null } catch { $contentionRejected = $true }
    Assert-True $contentionRejected 'A competing proxy-pool writer entered the locked critical section.'
  } finally {
    Exit-ZtgProxyPoolLock -LockHandle $firstLock
  }
  $secondLock = Enter-ZtgProxyPoolLock -DataRoot $temp -TimeoutSeconds 1
  Exit-ZtgProxyPoolLock -LockHandle $secondLock
  foreach ($writer in @('scripts\windows\run-proxy-selector.ps1','scripts\windows\manage-proxy-pool.ps1')) {
    $writerSource = Get-Content -LiteralPath (Join-Path $root $writer) -Raw
    Assert-True $writerSource.Contains('Enter-ZtgProxyPoolLock') "Shared proxy-pool lock missing from $writer."
  }
  $read = Get-ZtgProxyPool -DataRoot $temp -Version '1.4.0-dev'
  Assert-Equal @($read.nodes).Count 2 'Pool state should round-trip.'
  $statePath = Join-Path (Join-Path $temp 'state') 'proxy-pool.json'
  $invalidPool = Get-Content -LiteralPath $statePath -Raw | ConvertFrom-Json
  $invalidPool.objectType = 'rate-limit'
  [IO.File]::WriteAllText($statePath, ($invalidPool | ConvertTo-Json -Depth 12), (New-Object Text.UTF8Encoding($false)))
  $identityRejected = $false
  try { Get-ZtgProxyPool -DataRoot $temp -Version '1.4.0-dev' | Out-Null } catch { $identityRejected = $true }
  Assert-True $identityRejected 'Proxy pool accepted the wrong object type.'
  Save-ZtgProxyPool -Pool $selection.Pool -DataRoot $temp | Out-Null
  $paths = Get-ZtgProxyRuntimePaths -DataRoot $temp
  [IO.Directory]::CreateDirectory($paths.Directory) | Out-Null
  Assert-True (-not (Test-ZtgProxyRuntimeRunning -DataRoot $temp)) 'Missing PID record must report a stopped runtime.'
  @{ pid = 2147483647; executable = 'C:\missing\sing-box.exe' } | ConvertTo-Json | Set-Content -LiteralPath $paths.Pid -Encoding UTF8
  Assert-True (-not (Test-ZtgProxyRuntimeRunning -DataRoot $temp)) 'A stale PID record must not report a running runtime.'
  Remove-Item -LiteralPath $paths.Pid -Force
  [IO.File]::WriteAllText($paths.Stdout, ('x' * 1024), (New-Object Text.UTF8Encoding($false)))
  Assert-True (-not (Test-ZtgProxyRuntimeLogBudget -DataRoot $temp -MaxBytes 1024)) 'Runtime log budget must detect a full log.'
  Rotate-ZtgProxyRuntimeLogs -DataRoot $temp -MaxBytes 1024
  Assert-True (Test-Path -LiteralPath "$($paths.Stdout).1") 'Runtime log rotation must retain one bounded backup.'
  Assert-True (Test-ZtgProxyRuntimeLogBudget -DataRoot $temp -MaxBytes 1024) 'Rotated runtime logs must return below budget.'
  $currentConfig = New-ZtgSingBoxProxyConfig -Pool $selection.Pool -SelectedNode $selection.SelectedNode
  [IO.File]::WriteAllText($paths.Config, $currentConfig, (New-Object Text.UTF8Encoding($false)))
  Assert-True (Test-ZtgProxyRuntimeConfigCurrent -Pool $selection.Pool -SelectedNode $selection.SelectedNode -DataRoot $temp) 'Rendered runtime config should be current.'
  Update-ZtgProxyNode -Pool $selection.Pool -Name 'tokyo' -Server '10.246.77.4' | Out-Null
  Assert-True (-not (Test-ZtgProxyRuntimeConfigCurrent -Pool $selection.Pool -SelectedNode $selection.SelectedNode -DataRoot $temp)) 'Updating the selected node must invalidate the runtime config.'
} finally {
  if (Test-Path -LiteralPath $temp) { Remove-Item -LiteralPath $temp -Recurse -Force }
}

Write-Host 'ProxyPool tests passed.'
