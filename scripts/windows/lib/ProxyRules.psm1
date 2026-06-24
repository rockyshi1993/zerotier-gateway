Set-StrictMode -Version Latest

Import-Module (Join-Path $PSScriptRoot 'Common.psm1') -Force

function Get-ZtgProcessGroupRules {
  param([string[]]$Groups)

  $names = New-Object System.Collections.Generic.List[string]
  $paths = New-Object System.Collections.Generic.List[string]
  $regex = New-Object System.Collections.Generic.List[string]

  foreach ($group in $Groups) {
    switch ($group) {
      'remote-tools' {
        $names.Add('mstsc.exe')
        $names.Add('msrdc.exe')
        $regex.Add('.*(RemoteTool|RemoteControl|Relay|Helper).*\.exe$')
      }
      'chat-tools' {
        $names.Add('WeChat.exe')
      }
      'game-tools' {
        $names.Add('steam.exe')
      }
    }
  }

  [pscustomobject]@{
    ProcessNames = @($names | Select-Object -Unique)
    ProcessPaths = @($paths | Select-Object -Unique)
    ProcessPathRegex = @($regex | Select-Object -Unique)
  }
}

function Convert-ZtgUIntToIp {
  param([uint64]$Value)
  return @(
    (($Value -shr 24) -band 255),
    (($Value -shr 16) -band 255),
    (($Value -shr 8) -band 255),
    ($Value -band 255)
  ) -join '.'
}

function Convert-ZtgCidrToPacNet {
  param([Parameter(Mandatory)][string]$Cidr)

  $parts = $Cidr.Split('/')
  if ($parts.Count -ne 2) {
    throw "Invalid CIDR rule: $Cidr"
  }

  $ipParts = $parts[0].Split('.') | ForEach-Object { [uint64]$_ }
  $prefix = [int]$parts[1]
  if ($ipParts.Count -ne 4 -or $prefix -lt 0 -or $prefix -gt 32) {
    throw "Invalid CIDR rule: $Cidr"
  }

  $ipValue = ($ipParts[0] -shl 24) -bor ($ipParts[1] -shl 16) -bor ($ipParts[2] -shl 8) -bor $ipParts[3]
  $maskValue = if ($prefix -eq 0) {
    [uint64]0
  } else {
    [uint64]([math]::Pow(2, 32) - [math]::Pow(2, 32 - $prefix))
  }
  $networkValue = $ipValue -band $maskValue

  return @{
    address = Convert-ZtgUIntToIp -Value $networkValue
    mask = Convert-ZtgUIntToIp -Value $maskValue
  }
}

function New-ZtgPacContent {
  param([Parameter(Mandatory)][System.Collections.IDictionary]$Config)

  $domains = @(Split-ZtgCsv $Config['DIRECT_DOMAINS'])
  $suffixes = @(Split-ZtgCsv $Config['DIRECT_DOMAIN_SUFFIXES'])
  $cidrs = @(Split-ZtgCsv $Config['DIRECT_IP_CIDRS'])
  $directNets = @($cidrs | ForEach-Object { Convert-ZtgCidrToPacNet -Cidr $_ })

  $hostsJson = ConvertTo-Json -InputObject @($domains) -Compress
  $suffixJson = ConvertTo-Json -InputObject @($suffixes) -Compress
  $netsJson = ConvertTo-Json -InputObject @($directNets) -Depth 4 -Compress

  if (-not $hostsJson) { $hostsJson = '[]' }
  if (-not $suffixJson) { $suffixJson = '[]' }
  if (-not $netsJson) { $netsJson = '[]' }

  $proxyHost = if ($Config.Contains('PROXY_CONNECT_HOST') -and -not [string]::IsNullOrWhiteSpace([string]$Config['PROXY_CONNECT_HOST'])) {
    [string]$Config['PROXY_CONNECT_HOST']
  } else {
    [string]$Config['UBUNTU_ZT_IP']
  }

  $template = Get-Content -Raw -LiteralPath (Join-Path (Get-ZtgProjectRoot) 'templates/pac/proxy.pac.tmpl')
  $template = $template.Replace('${PROXY_HOST}', $proxyHost)
  $template = $template.Replace('${PROXY_PORT}', [string]$Config['PROXY_PORT'])
  $template = $template.Replace('${DIRECT_HOSTS_JSON}', $hostsJson)
  $template = $template.Replace('${DIRECT_SUFFIXES_JSON}', $suffixJson)
  $template = $template.Replace('${DIRECT_NETS_JSON}', $netsJson)
  return $template
}

function New-ZtgClientRulesContent {
  param([Parameter(Mandatory)][System.Collections.IDictionary]$Config)

  $groups = @(Split-ZtgCsv $Config['DIRECT_PROCESS_GROUPS'])
  $groupRules = Get-ZtgProcessGroupRules -Groups $groups
  $processNames = @(@(Split-ZtgCsv $Config['DIRECT_PROCESS_NAMES']) + @($groupRules.ProcessNames) | Select-Object -Unique)
  $processPaths = @(@(Split-ZtgCsv $Config['DIRECT_PROCESS_PATHS']) + @($groupRules.ProcessPaths) | Select-Object -Unique)
  $processRegex = @(@(Split-ZtgCsv $Config['DIRECT_PROCESS_PATH_REGEX']) + @($groupRules.ProcessPathRegex) | Select-Object -Unique)

  $rules = @()
  $domainRule = [ordered]@{ action = 'route'; outbound = 'direct' }
  $domains = @(Split-ZtgCsv $Config['DIRECT_DOMAINS'])
  $suffixes = @(Split-ZtgCsv $Config['DIRECT_DOMAIN_SUFFIXES'])
  $cidrs = @(Split-ZtgCsv $Config['DIRECT_IP_CIDRS'])
  if ($domains.Count -gt 0) { $domainRule.domain = $domains }
  if ($suffixes.Count -gt 0) { $domainRule.domain_suffix = $suffixes }
  if ($cidrs.Count -gt 0) { $domainRule.ip_cidr = $cidrs }
  if ($domainRule.Count -gt 1) { $rules += $domainRule }

  $processRule = [ordered]@{ action = 'route'; outbound = 'direct' }
  if ($processNames.Count -gt 0) { $processRule.process_name = $processNames }
  if ($processPaths.Count -gt 0) { $processRule.process_path = $processPaths }
  if ($processRegex.Count -gt 0) { $processRule.process_path_regex = $processRegex }
  if ($processRule.Count -gt 1) { $rules += $processRule }

  $rulesJson = ConvertTo-Json -InputObject @($rules) -Depth 8 -Compress
  if (-not $rulesJson) { $rulesJson = '[]' }

  $hasProxyUsername = $Config.Contains('PROXY_USERNAME') -and -not [string]::IsNullOrWhiteSpace([string]$Config['PROXY_USERNAME'])
  $hasProxyPassword = $Config.Contains('PROXY_PASSWORD') -and -not [string]::IsNullOrWhiteSpace([string]$Config['PROXY_PASSWORD'])
  if ($hasProxyUsername -xor $hasProxyPassword) {
    throw 'PROXY_USERNAME and PROXY_PASSWORD must be set together, or both left empty to disable proxy authentication.'
  }

  $authJson = ''
  if ($hasProxyUsername -and $hasProxyPassword) {
    $usernameJson = ConvertTo-Json -InputObject ([string]$Config['PROXY_USERNAME']) -Compress
    $passwordJson = ConvertTo-Json -InputObject ([string]$Config['PROXY_PASSWORD']) -Compress
    $authJson = ",`n      `"username`": $usernameJson,`n      `"password`": $passwordJson"
  }

  $proxyHost = if ($Config.Contains('PROXY_CONNECT_HOST') -and -not [string]::IsNullOrWhiteSpace([string]$Config['PROXY_CONNECT_HOST'])) {
    [string]$Config['PROXY_CONNECT_HOST']
  } else {
    [string]$Config['UBUNTU_ZT_IP']
  }

  $template = Get-Content -Raw -LiteralPath (Join-Path (Get-ZtgProjectRoot) 'templates/sing-box/windows-local-client.json.tmpl')
  $template = $template.Replace('${LOCAL_PROXY_PORT}', [string]$Config['LOCAL_PROXY_PORT'])
  $template = $template.Replace('${PROXY_CONNECT_HOST}', $proxyHost)
  $template = $template.Replace('${PROXY_PORT}', [string]$Config['PROXY_PORT'])
  $template = $template.Replace('${CLIENT_PROXY_AUTH_JSON}', $authJson)
  $template = $template.Replace('${ROUTE_RULES_JSON}', $rulesJson)
  return $template
}

Export-ModuleMember -Function Get-ZtgProcessGroupRules,New-ZtgPacContent,New-ZtgClientRulesContent
