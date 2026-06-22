# Install Guide

## Overview

Use one ZeroTier private network for:

1. Ubuntu server as the private proxy node.
2. Home PC and Work PC as remote nodes.
3. Optional relay only when direct connectivity is poor.

## 1. Get The Repository

Ubuntu:

```bash
git clone https://github.com/rockyshi1993/zerotier-gateway.git
cd zerotier-gateway
```

Windows PowerShell:

```powershell
git clone https://github.com/rockyshi1993/zerotier-gateway.git
cd .\zerotier-gateway
```

## 2. Prepare `.env`

Copy the example config:

```bash
cp config/example.env .env
```

Windows:

```powershell
Copy-Item .\config\example.env .\.env
```

Edit `.env` and fill at least:

```text
ZEROTIER_NETWORK_ID=
PROXY_USERNAME=
PROXY_PASSWORD=
```

Scripts read `.env` by default. Use `--env <path>` or `-Env <path>` only when the config file is not in the project root.

## 3. Ubuntu

Preview first:

```bash
sudo bash scripts/ubuntu/install.sh --dry-run
```

Install:

```bash
sudo bash scripts/ubuntu/install.sh
```

Then authorize the Ubuntu node in ZeroTier Central and assign `10.246.77.1`.

Check status:

```bash
sudo bash scripts/ubuntu/health-check.sh
```

## 4. Windows

Run PowerShell as administrator.

Home PC:

```powershell
.\scripts\windows\setup.ps1 -Role Home
```

Work PC:

```powershell
.\scripts\windows\setup.ps1 -Role Work
```

After reviewing firewall rules, apply them explicitly:

```powershell
.\scripts\windows\setup.ps1 -Role Home -ApplyFirewall
```

## 5. Verify

```powershell
.\scripts\windows\test-network.ps1
.\scripts\windows\test-proxy.ps1
```
