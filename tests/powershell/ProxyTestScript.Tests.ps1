$ErrorActionPreference = 'Stop'

$root = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$scriptPath = Join-Path $root 'scripts\windows\test-proxy.ps1'
$source = Get-Content -Raw -LiteralPath $scriptPath
$tokens = $null
$errors = $null
[System.Management.Automation.Language.Parser]::ParseFile($scriptPath, [ref]$tokens, [ref]$errors) | Out-Null
if ($errors.Count -gt 0) {
  throw "Proxy test script has parse errors: $($errors[0].Message)"
}

foreach ($required in @('TcpTestSucceeded', 'curl.exe', '--proxy', 'Proxy endpoint and exit URL checks passed', 'SkipExitCheck')) {
  if ($source -notmatch [regex]::Escape($required)) {
    throw "Proxy test script is missing required validation behavior: $required"
  }
}

$help = & powershell -NoProfile -ExecutionPolicy Bypass -File $scriptPath -Help 2>&1 | Out-String
if ($LASTEXITCODE -ne 0 -or $help -notmatch 'SkipExitCheck') {
  throw 'Proxy test help path failed.'
}

Write-Host 'ProxyTestScript.Tests.ps1 passed'
