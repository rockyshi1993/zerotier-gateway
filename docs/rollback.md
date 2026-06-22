# Rollback

## Ubuntu

```bash
sudo bash scripts/ubuntu/uninstall.sh
```

This removes the managed proxy service. It does not uninstall ZeroTier by default.

Disable relay:

```bash
sudo bash scripts/ubuntu/disable-relay.sh
```

## Windows

Remove firewall rules created by this project:

```powershell
.\scripts\windows\setup.ps1 -Rollback
```

Generated PAC and local client configs are written under `artifacts/` and can be removed manually.
