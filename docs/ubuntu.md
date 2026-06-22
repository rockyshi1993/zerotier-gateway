# Ubuntu Server

The Ubuntu server provides:

- ZeroTier membership.
- Private HTTP/SOCKS5 proxy through sing-box.
- Optional relay fallback.

## Commands

```bash
sudo bash scripts/ubuntu/install.sh --dry-run
sudo bash scripts/ubuntu/install.sh
sudo bash scripts/ubuntu/health-check.sh
```

## Proxy Binding

The proxy must bind to the Ubuntu ZeroTier IP:

```text
PROXY_BIND_IP=10.246.77.1
PROXY_PORT=10808
```

Do not bind the proxy to `0.0.0.0`.

## Systemd

The proxy service is rendered from:

```text
templates/systemd/sing-box-zt-proxy.service.tmpl
```

The generated runtime config is intended for:

```text
/etc/zerotier-gateway/sing-box-server.json
```
