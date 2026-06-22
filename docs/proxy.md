# Proxy Guide

Ubuntu provides a private mixed HTTP/SOCKS5 proxy through sing-box.

Default endpoint:

```text
10.246.77.1:10808
```

Use it only in software that needs proxy access. Software without proxy settings keeps using the original network.

## Test

```powershell
.\scripts\windows\test-proxy.ps1
```

## Generate PAC

```powershell
.\scripts\windows\generate-proxy-pac.ps1
```

Output:

```text
artifacts/proxy.pac
```

## Generate Local Client Rules

```powershell
.\scripts\windows\generate-client-rules.ps1
```

Output:

```text
artifacts/windows-local-client.json
```
