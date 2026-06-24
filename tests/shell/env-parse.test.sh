#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
bash "$ROOT/scripts/ubuntu/install.sh" --env "$ROOT/tests/fixtures/example.env" --dry-run

tmp_env="$(mktemp)"
tmp_no_auth_env="$(mktemp)"
tmp_half_auth_env="$(mktemp)"
tmp_public_env="$(mktemp)"
tmp_bad_public_env="$(mktemp)"
trap 'rm -f "$tmp_env" "$tmp_no_auth_env" "$tmp_half_auth_env" "$tmp_public_env" "$tmp_bad_public_env" "$ROOT/artifacts/sing-box-server.json"' EXIT
cat > "$tmp_env" <<'ENV'
ZEROTIER_NETWORK_ID=0123456789abcdef
PROXY_USERNAME=test-user
PROXY_PASSWORD='pa|ss&word'
ENV

bash "$ROOT/scripts/ubuntu/install-proxy.sh" --env "$tmp_env" --dry-run
if grep -q '\${PROXY_PORT}' "$ROOT/artifacts/sing-box-server.json"; then
  echo "template default placeholder was not rendered" >&2
  exit 1
fi
if ! grep -q '"users"' "$ROOT/artifacts/sing-box-server.json"; then
  echo "proxy auth users were not rendered when credentials are set" >&2
  exit 1
fi

cat > "$tmp_no_auth_env" <<'ENV'
ZEROTIER_NETWORK_ID=0123456789abcdef
ENV

bash "$ROOT/scripts/ubuntu/install-proxy.sh" --env "$tmp_no_auth_env" --dry-run
if grep -q '"users"' "$ROOT/artifacts/sing-box-server.json"; then
  echo "proxy auth users should not be rendered by default" >&2
  exit 1
fi

cat > "$tmp_half_auth_env" <<'ENV'
ZEROTIER_NETWORK_ID=0123456789abcdef
PROXY_USERNAME=test-user
ENV

if bash "$ROOT/scripts/ubuntu/install-proxy.sh" --env "$tmp_half_auth_env" --dry-run; then
  echo "half proxy credentials should fail validation" >&2
  exit 1
fi

cat > "$tmp_bad_public_env" <<'ENV'
ZEROTIER_NETWORK_ID=0123456789abcdef
PROXY_BIND_IP=0.0.0.0
ENV

if bash "$ROOT/scripts/ubuntu/install-proxy.sh" --env "$tmp_bad_public_env" --dry-run; then
  echo "public bind should require PROXY_PUBLIC_ACCESS=true" >&2
  exit 1
fi

cat > "$tmp_public_env" <<'ENV'
ZEROTIER_NETWORK_ID=0123456789abcdef
PROXY_BIND_IP=0.0.0.0
PROXY_PUBLIC_ACCESS=true
PROXY_CONNECT_HOST=203.0.113.10
PROXY_ALLOWED_CLIENT_CIDRS=198.51.100.23/32
ENV

bash "$ROOT/scripts/ubuntu/install-proxy.sh" --env "$tmp_public_env" --dry-run
