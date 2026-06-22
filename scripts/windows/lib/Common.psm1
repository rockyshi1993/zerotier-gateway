Set-StrictMode -Version Latest

function Get-ZtgProjectRoot {
  $moduleDir = $PSScriptRoot
  return (Resolve-Path (Join-Path $moduleDir '..\..\..')).Path
}

function Write-ZtgInfo {
  param([Parameter(Mandatory)][string]$Message)
  Write-Host "[INFO] $Message"
}

function Write-ZtgWarn {
  param([Parameter(Mandatory)][string]$Message)
  Write-Warning $Message
}

function Split-ZtgCsv {
  param([AllowNull()][string]$Value)
  if ([string]::IsNullOrWhiteSpace($Value)) {
    return @()
  }
  return @($Value -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ })
}

function Resolve-ZtgPath {
  param([Parameter(Mandatory)][string]$Path)
  if ([System.IO.Path]::IsPathRooted($Path)) {
    return $Path
  }
  return (Join-Path (Get-ZtgProjectRoot) $Path)
}

Export-ModuleMember -Function Get-ZtgProjectRoot,Write-ZtgInfo,Write-ZtgWarn,Split-ZtgCsv,Resolve-ZtgPath
