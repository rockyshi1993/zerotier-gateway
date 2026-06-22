# Windows Client

Run scripts from an administrator PowerShell when changing firewall rules.

## Setup

Home PC:

```powershell
.\scripts\windows\setup.ps1 -Role Home
```

Work PC:

```powershell
.\scripts\windows\setup.ps1 -Role Work
```

The script prints a firewall plan first. Add `-ApplyFirewall` only after checking the plan.

## Diagnostics

```powershell
.\scripts\windows\test-network.ps1
.\scripts\windows\test-proxy.ps1
.\scripts\windows\show-diagnostics.ps1 -FindProcess "remote"
```

## Config Path

The default config path is `.env` in the project root.

Use this only for non-default config locations:

```powershell
.\scripts\windows\test-network.ps1 -Env .\profiles\office.env
```
