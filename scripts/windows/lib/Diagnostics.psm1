Set-StrictMode -Version Latest

function Find-ZtgProcess {
  param([Parameter(Mandatory)][string]$Pattern)

  Get-Process | Where-Object {
    $_.ProcessName -match $Pattern -or ($_.Path -and $_.Path -match $Pattern)
  } | Select-Object ProcessName, Id, Path
}

function Find-ZtgProcessPath {
  param([Parameter(Mandatory)][string]$Path)

  Get-Process | Where-Object {
    $_.Path -and $_.Path -like (Join-Path $Path '*')
  } | Select-Object ProcessName, Id, Path
}

Export-ModuleMember -Function Find-ZtgProcess,Find-ZtgProcessPath
