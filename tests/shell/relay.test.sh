#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
tmp_env="$(mktemp)"
tmp_second_relay_env="$(mktemp)"
trap 'rm -f "$tmp_env" "$tmp_second_relay_env"' EXIT

output="$(bash "$ROOT/scripts/ubuntu/install-relay.sh" --env "$ROOT/tests/fixtures/example.env" --dry-run 2>&1)"

case "$output" in
  *"Company connects here to reach Home: 10.246.77.1:443 -> 10.246.77.10:3389"*) ;;
  *) echo "home relay dry-run plan was not rendered" >&2; exit 1 ;;
esac

case "$output" in
  *"Home connects here to reach Work: 10.246.77.1:444 -> 10.246.77.20:3389"*) ;;
  *) echo "work relay dry-run plan was not rendered" >&2; exit 1 ;;
esac

case "$output" in
  *"[DRY-RUN] write /etc/systemd/system/zerotier-gateway-relay-home-3389.socket"*) ;;
  *) echo "home relay socket unit was not planned" >&2; exit 1 ;;
esac

case "$output" in
  *"[DRY-RUN] remove any /etc/systemd/system/zerotier-gateway-relay-*.socket"*) ;;
  *) echo "stale relay socket cleanup was not planned before install" >&2; exit 1 ;;
esac

cat > "$tmp_second_relay_env" <<'ENV'
ZEROTIER_NETWORK_ID=0123456789abcdef
UBUNTU_ZT_IP=10.246.77.2
HOME_PC_ZT_IP=10.246.77.10
WORK_PC_ZT_IP=10.246.77.20
RELAY_PORT=443
REMOTE_PORTS=3389
ENV

second_output="$(bash "$ROOT/scripts/ubuntu/install-relay.sh" --env "$tmp_second_relay_env" --dry-run 2>&1)"

case "$second_output" in
  *"Company connects here to reach Home: 10.246.77.2:443 -> 10.246.77.10:3389"*) ;;
  *) echo "second relay server should listen on its own ZeroTier IP for home relay" >&2; exit 1 ;;
esac

case "$second_output" in
  *"Home connects here to reach Work: 10.246.77.2:444 -> 10.246.77.20:3389"*) ;;
  *) echo "second relay server should listen on its own ZeroTier IP for work relay" >&2; exit 1 ;;
esac

if ! grep -q '^FreeBind=true$' "$ROOT/templates/systemd/zerotier-tcp-relay.socket.tmpl"; then
  echo "relay socket template should use FreeBind=true for ZeroTier IP startup ordering" >&2
  exit 1
fi

disable_output="$(bash "$ROOT/scripts/ubuntu/disable-relay.sh" --env "$ROOT/tests/fixtures/example.env" --dry-run 2>&1)"

case "$disable_output" in
  *"[DRY-RUN] systemctl disable --now zerotier-gateway-relay-home-3389.socket"*) ;;
  *) echo "home relay socket disable was not planned" >&2; exit 1 ;;
esac

case "$disable_output" in
  *"[DRY-RUN] remove any /etc/systemd/system/zerotier-gateway-relay-*.service"*) ;;
  *) echo "stale relay service cleanup was not planned during disable" >&2; exit 1 ;;
esac

cat > "$tmp_env" <<'ENV'
ZEROTIER_NETWORK_ID=0123456789abcdef
REMOTE_PORTS=,
ENV

if bash "$ROOT/scripts/ubuntu/install-relay.sh" --env "$tmp_env" --dry-run >/dev/null 2>&1; then
  echo "empty REMOTE_PORTS should fail relay validation" >&2
  exit 1
fi

echo "relay.test.sh passed"
