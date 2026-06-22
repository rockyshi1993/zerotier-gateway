Set-StrictMode -Version Latest

function Test-ZtgZeroTierCli {
  return [bool](Get-Command zerotier-cli -ErrorAction SilentlyContinue)
}

function Get-ZtgZeroTierStatus {
  if (Test-ZtgZeroTierCli) {
    zerotier-cli status
    zerotier-cli listnetworks
    zerotier-cli peers
  } else {
    Write-Warning 'zerotier-cli was not found in PATH.'
  }
}

Export-ModuleMember -Function Test-ZtgZeroTierCli,Get-ZtgZeroTierStatus
