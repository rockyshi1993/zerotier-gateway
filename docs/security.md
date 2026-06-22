# Security Notes

## Required Defaults

- ZeroTier network should be private.
- New devices must be authorized manually.
- Proxy authentication must be enabled.
- Proxy must listen on the Ubuntu ZeroTier IP, not `0.0.0.0`.
- Remote ports must not be exposed to the public internet.
- `.env` must not be committed.

## Public Exposure

The proxy endpoint is intended for ZeroTier private access only:

```text
10.246.77.1:10808
```

Cloud firewalls and OS firewalls should not expose this port publicly.
