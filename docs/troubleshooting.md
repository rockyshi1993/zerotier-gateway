# Troubleshooting

## Config Not Found

Scripts default to `.env` in the project root.

Fix:

```bash
cp config/example.env .env
```

Windows:

```powershell
Copy-Item .\config\example.env .\.env
```

## ZeroTier Not Reachable

Check:

1. Devices are authorized in ZeroTier Central.
2. IP addresses are fixed as expected.
3. Windows firewall allows the peer ZeroTier IP.
4. Route for `10.246.77.0/24` uses ZeroTier.

Run:

```powershell
.\scripts\windows\test-network.ps1
```

## Proxy Not Reachable

Check:

1. Ubuntu has `10.246.77.1`.
2. sing-box service is running.
3. Proxy listens on `10.246.77.1:10808`.
4. Username and password are correct.

Run:

```powershell
.\scripts\windows\test-proxy.ps1
```

## Process Bypass Misses Traffic

Multi-process software may use services, helper processes, or updater processes.

Find candidates:

```powershell
.\scripts\windows\show-diagnostics.ps1 -FindProcess "remote"
.\scripts\windows\show-diagnostics.ps1 -FindProcessPath "C:\Program Files\RemoteTool"
```
