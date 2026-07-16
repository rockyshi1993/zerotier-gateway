Set-StrictMode -Version Latest

Import-Module (Join-Path $PSScriptRoot 'Common.psm1') -Force

function Get-ZtgDataRoot {
  param([string]$Root)
  if ($Root) { return [System.IO.Path]::GetFullPath($Root) }
  if ($env:ZTG_DATA_ROOT) { return [System.IO.Path]::GetFullPath($env:ZTG_DATA_ROOT) }
  return (Join-Path $env:ProgramData 'ZeroTierGateway')
}

function Get-ZtgStatePath {
  param(
    [Parameter(Mandatory)][string]$Name,
    [string]$Root
  )
  if ($Name -notmatch '^[A-Za-z0-9][A-Za-z0-9._-]{0,63}$') {
    throw "Invalid managed object name: $Name"
  }
  return (Join-Path (Join-Path (Get-ZtgDataRoot -Root $Root) 'state') "$Name.json")
}

function Read-ZtgJsonState {
  param(
    [Parameter(Mandatory)][string]$Name,
    [string]$Root,
    [string]$ExpectedObjectType,
    [string]$ExpectedObjectName
  )
  $path = Get-ZtgStatePath -Name $Name -Root $Root
  if (-not (Test-Path -LiteralPath $path)) { return $null }
  $state = Get-Content -LiteralPath $path -Raw | ConvertFrom-Json
  if ($state.PSObject.Properties.Name -notcontains 'schemaVersion' -or [int]$state.schemaVersion -ne 1) {
    $schema = if ($state.PSObject.Properties.Name -contains 'schemaVersion') { $state.schemaVersion } else { 'missing' }
    throw "Unsupported state schema $schema in $path."
  }
  if ($state.PSObject.Properties.Name -notcontains 'owner' -or [string]$state.owner -ne 'zerotier-gateway') {
    throw "State owner is not zerotier-gateway: $path"
  }
  if ($ExpectedObjectType) {
    if ($state.PSObject.Properties.Name -notcontains 'objectType' -or [string]$state.objectType -ne $ExpectedObjectType) {
      throw ('State object type is not {0}: {1}' -f $ExpectedObjectType, $path)
    }
  }
  if ($ExpectedObjectName) {
    if ($state.PSObject.Properties.Name -notcontains 'objectName' -or [string]$state.objectName -ne $ExpectedObjectName) {
      throw ('State object name is not {0}: {1}' -f $ExpectedObjectName, $path)
    }
  }
  return $state
}

function Write-ZtgJsonState {
  param(
    [Parameter(Mandatory)][string]$Name,
    [Parameter(Mandatory)]$Value,
    [string]$Root
  )
  $path = Get-ZtgStatePath -Name $Name -Root $Root
  $directory = Split-Path -Parent $path
  [System.IO.Directory]::CreateDirectory($directory) | Out-Null
  $temporary = Join-Path $directory ('.ztg-state-' + [guid]::NewGuid().ToString('N') + '.tmp')
  $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
  try {
    [System.IO.File]::WriteAllText($temporary, (($Value | ConvertTo-Json -Depth 12) + [Environment]::NewLine), $utf8NoBom)
    Move-Item -LiteralPath $temporary -Destination $path -Force
  } finally {
    if (Test-Path -LiteralPath $temporary) { Remove-Item -LiteralPath $temporary -Force }
  }
  return $path
}

function New-ZtgManagedState {
  param(
    [Parameter(Mandatory)][ValidateSet('installation','proxy-node','proxy-pool','rate-limit','publish-ip','publish-domain','publish-firewall')][string]$ObjectType,
    [Parameter(Mandatory)][string]$ObjectName,
    [Parameter(Mandatory)][string]$Version,
    [bool]$Enabled = $false,
    [hashtable]$Properties = @{}
  )
  if ($ObjectName -notmatch '^[A-Za-z0-9][A-Za-z0-9._-]{0,63}$') { throw "Invalid managed object name: $ObjectName" }
  $state = [ordered]@{
    schemaVersion = 1
    objectVersion = 1
    owner = 'zerotier-gateway'
    objectType = $ObjectType
    objectName = $ObjectName
    enabled = $Enabled
    lastAppliedVersion = $Version
    generation = 1
    updatedAt = [DateTime]::UtcNow.ToString('o')
  }
  foreach ($key in $Properties.Keys) { $state[$key] = $Properties[$key] }
  return [pscustomobject]$state
}

Export-ModuleMember -Function Get-ZtgDataRoot,Get-ZtgStatePath,Read-ZtgJsonState,Write-ZtgJsonState,New-ZtgManagedState
