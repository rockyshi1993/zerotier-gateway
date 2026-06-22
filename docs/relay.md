# Relay Fallback

Relay is optional.

Use it only when:

1. Home PC and Work PC are not DIRECT for a long time.
2. Remote access is clearly poor.
3. UDP/NAT conditions cannot be improved.

Preview:

```bash
sudo bash scripts/ubuntu/install-relay.sh --dry-run
```

Install or wire your relay service:

```bash
sudo bash scripts/ubuntu/install-relay.sh
```

Disable:

```bash
sudo bash scripts/ubuntu/disable-relay.sh
```

Relay should never replace normal DIRECT connectivity when DIRECT works well.
