Set-StrictMode -Version Latest

function Get-ZtgRouteSummary {
  param([Parameter(Mandatory)][hashtable]$Config)
  Get-NetRoute -DestinationPrefix $Config['ZEROTIER_SUBNET'] -ErrorAction SilentlyContinue |
    Select-Object DestinationPrefix, InterfaceAlias, NextHop, RouteMetric
}

Export-ModuleMember -Function Get-ZtgRouteSummary
