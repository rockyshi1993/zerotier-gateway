Set-StrictMode -Version Latest

function Get-ZtgRemotePeerIp {
  param(
    [Parameter(Mandatory)][System.Collections.IDictionary]$Config,
    [Parameter(Mandatory)][ValidateSet('Home','Work')]$Role
  )
  if ($Role -eq 'Home') {
    return $Config['WORK_PC_ZT_IP']
  }
  return $Config['HOME_PC_ZT_IP']
}

function New-ZtgFirewallPlan {
  param(
    [Parameter(Mandatory)][System.Collections.IDictionary]$Config,
    [Parameter(Mandatory)][ValidateSet('Home','Work')]$Role
  )

  $remoteIp = Get-ZtgRemotePeerIp -Config $Config -Role $Role
  $ports = @([string]$Config['REMOTE_PORTS'] -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ })
  foreach ($port in $ports) {
    [pscustomobject]@{
      DisplayName = "ZT Gateway Remote Inbound $Role $port"
      Direction = 'Inbound'
      Protocol = 'TCP'
      LocalPort = $port
      RemoteAddress = $remoteIp
      Action = 'Allow'
    }
  }
}

function Test-ZtgWindowsAdministrator {
  $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
  $principal = [Security.Principal.WindowsPrincipal]::new($identity)
  return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Assert-ZtgFirewallAdministrator {
  if (-not (Test-ZtgWindowsAdministrator)) {
    throw 'Firewall changes require an elevated PowerShell. Right-click PowerShell, choose Run as administrator, run Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass, then retry the command.'
  }
}

function Apply-ZtgFirewallPlan {
  param([Parameter(Mandatory)]$Plan)

  Assert-ZtgFirewallAdministrator
  foreach ($rule in $Plan) {
    Get-NetFirewallRule -DisplayName $rule.DisplayName -ErrorAction SilentlyContinue | Remove-NetFirewallRule -ErrorAction Stop
    New-NetFirewallRule -DisplayName $rule.DisplayName -Direction Inbound -Protocol $rule.Protocol -LocalPort $rule.LocalPort -RemoteAddress $rule.RemoteAddress -Action Allow -ErrorAction Stop | Out-Null
  }
}

function Remove-ZtgFirewallRules {
  Assert-ZtgFirewallAdministrator
  Get-NetFirewallRule -DisplayName 'ZT Gateway Remote Inbound *' -ErrorAction SilentlyContinue | Remove-NetFirewallRule -ErrorAction Stop
}

Export-ModuleMember -Function Get-ZtgRemotePeerIp,New-ZtgFirewallPlan,Test-ZtgWindowsAdministrator,Assert-ZtgFirewallAdministrator,Apply-ZtgFirewallPlan,Remove-ZtgFirewallRules
