# Proxy Bypass Rules

Use bypass rules when some traffic should not go through the Ubuntu proxy.

## Domain And IP Rules

Edit `.env`:

```text
DIRECT_DOMAINS=localhost,*.local,*.company.com
DIRECT_DOMAIN_SUFFIXES=.local
DIRECT_IP_CIDRS=10.246.77.0/24,10.0.0.0/8,172.16.0.0/12,192.168.0.0/16
```

Generate PAC:

```powershell
.\scripts\windows\generate-proxy-pac.ps1
```

## Process Rules

Process rules require a local rule client on Windows. Ubuntu cannot know which Windows process sent a request.

Edit `.env`:

```text
PROXY_MODE=local-rule-client
DIRECT_PROCESS_GROUPS=remote-tools,chat-tools,game-tools
DIRECT_PROCESS_NAMES=
DIRECT_PROCESS_PATHS=
DIRECT_PROCESS_PATH_REGEX=
```

Generate local client rules:

```powershell
.\scripts\windows\generate-client-rules.ps1
```

## Multi-Process Software

For multi-process software, prefer:

1. Application group.
2. Installation directory.
3. Path regex.
4. Complete process name list.

Do not rely on one main executable only.
