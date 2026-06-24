#!/usr/bin/env bash

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
tmp_env="$(mktemp)"
trap 'rm -f "$tmp_env"' EXIT

printf '0123456789abcdef\n\n\n\n\n\nn\n' | bash "$ROOT/scripts/ubuntu/init-config.sh" --env "$tmp_env" >/dev/null

grep -q '^ZEROTIER_NETWORK_ID=0123456789abcdef$' "$tmp_env"
grep -q '^UBUNTU_ZT_IP=10.246.77.1$' "$tmp_env"
grep -q '^HOME_PC_ZT_IP=10.246.77.10$' "$tmp_env"
grep -q '^WORK_PC_ZT_IP=10.246.77.20$' "$tmp_env"
grep -q '^PROXY_USERNAME=$' "$tmp_env"
grep -q '^PROXY_PASSWORD=$' "$tmp_env"

printf 'fedcba9876543210\n10.99.0.0/24\n10.99.0.1\n10.99.0.10\n10.99.0.20\n18080\ny\nproxy-user\nproxy-pass\n' | bash "$ROOT/scripts/ubuntu/init-config.sh" --env "$tmp_env" >/dev/null

grep -q '^ZEROTIER_NETWORK_ID=fedcba9876543210$' "$tmp_env"
grep -q '^ZEROTIER_SUBNET=10.99.0.0/24$' "$tmp_env"
grep -q '^PROXY_BIND_IP=10.99.0.1$' "$tmp_env"
grep -q '^PROXY_PORT=18080$' "$tmp_env"
grep -q '^PROXY_USERNAME=proxy-user$' "$tmp_env"
grep -q '^PROXY_PASSWORD=proxy-pass$' "$tmp_env"

echo "init-config.test.sh passed"
