# Remote Access

Use ZeroTier IPs for remote access.

Default IP plan:

| Device | ZeroTier IP |
|---|---|
| Ubuntu server | `10.246.77.1` |
| Home PC | `10.246.77.10` |
| Work PC | `10.246.77.20` |

## Direction

Work PC to Home PC:

```text
10.246.77.10
```

Home PC to Work PC:

```text
10.246.77.20
```

## Firewall

Only allow the peer ZeroTier IP to access remote ports.

Preview:

```powershell
.\scripts\windows\set-firewall-rules.ps1 -Role Home
```

Apply:

```powershell
.\scripts\windows\set-firewall-rules.ps1 -Role Home -Apply
```

Do not expose remote desktop or remote control ports to the public internet.
