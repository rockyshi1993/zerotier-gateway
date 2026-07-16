$ErrorActionPreference = 'Stop'
$root = Resolve-Path (Join-Path $PSScriptRoot '..\..')
Import-Module (Join-Path $root 'scripts\windows\lib\State.psm1') -Force

$temp = Join-Path ([System.IO.Path]::GetTempPath()) ('ztg-state-test-' + [guid]::NewGuid().ToString('N'))
try {
  $state = New-ZtgManagedState -ObjectType installation -ObjectName host -Version '1.4.0-dev' -Properties @{ sourceHead = 'abc123' }
  $path = Write-ZtgJsonState -Name installation -Value $state -Root $temp
  if (-not (Test-Path -LiteralPath $path)) { throw 'State file was not written.' }
  $read = Read-ZtgJsonState -Name installation -Root $temp -ExpectedObjectType installation -ExpectedObjectName host
  if ($read.owner -ne 'zerotier-gateway') { throw 'Unexpected state owner.' }
  if ($read.lastAppliedVersion -ne '1.4.0-dev') { throw 'Unexpected installed version.' }
  foreach ($mutation in @(
    @{ Property = 'schemaVersion'; Value = 2; Type = 'installation'; Name = 'host' },
    @{ Property = 'objectType'; Value = 'rate-limit'; Type = 'installation'; Name = 'host' },
    @{ Property = 'objectName'; Value = 'wrong-object'; Type = 'installation'; Name = 'host' }
  )) {
    $copy = $state | ConvertTo-Json -Depth 12 | ConvertFrom-Json
    $copy.($mutation.Property) = $mutation.Value
    Write-ZtgJsonState -Name invalid -Value $copy -Root $temp | Out-Null
    $invalidRejected = $false
    try { Read-ZtgJsonState -Name invalid -Root $temp -ExpectedObjectType $mutation.Type -ExpectedObjectName $mutation.Name | Out-Null } catch { $invalidRejected = $true }
    if (-not $invalidRejected) { throw "Invalid state $($mutation.Property) was accepted." }
  }
  $missingSchema = $state | Select-Object * -ExcludeProperty schemaVersion
  Write-ZtgJsonState -Name missing-schema -Value $missingSchema -Root $temp | Out-Null
  $missingRejected = $false
  try { Read-ZtgJsonState -Name missing-schema -Root $temp -ExpectedObjectType installation -ExpectedObjectName host | Out-Null } catch { $missingRejected = $true }
  if (-not $missingRejected) { throw 'Missing state schema was accepted.' }
  $rejected = $false
  try { Get-ZtgStatePath -Name '..\escape' -Root $temp | Out-Null } catch { $rejected = $true }
  if (-not $rejected) { throw 'Traversal name was accepted.' }
  Write-Host 'State tests passed.'
} finally {
  if (Test-Path -LiteralPath $temp) { Remove-Item -LiteralPath $temp -Recurse -Force }
}
