#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
bash "$ROOT/scripts/ubuntu/install.sh" --env "$ROOT/tests/fixtures/example.env" --dry-run

tmp_env="$(mktemp)"
trap 'rm -f "$tmp_env" "$ROOT/artifacts/sing-box-server.json"' EXIT
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
