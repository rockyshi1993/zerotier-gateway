$ErrorActionPreference = 'Stop'

$root = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$scriptPath = Join-Path $root 'scripts\windows\enable-remote-desktop.ps1'
$source = Get-Content -Raw -LiteralPath $scriptPath
$tokens = $null
$errors = $null
[System.Management.Automation.Language.Parser]::ParseFile($scriptPath, [ref]$tokens, [ref]$errors) | Out-Null
if ($errors.Count -gt 0) {
  throw "Remote Desktop script has parse errors: $($errors[0].Message)"
}

foreach ($required in @('fDenyTSConnections', 'UserAuthentication', 'TermService', 'Administrator PowerShell', 'Home')) {
  if ($source -notmatch [regex]::Escape($required)) {
    throw "Remote Desktop script is missing required behavior: $required"
  }
}

$help = & powershell -NoProfile -ExecutionPolicy Bypass -File $scriptPath -Help 2>&1 | Out-String
if ($LASTEXITCODE -ne 0 -or $help -notmatch '\-Apply') {
  throw 'Remote Desktop help path failed.'
}

Write-Host 'RemoteDesktop.Tests.ps1 passed'
