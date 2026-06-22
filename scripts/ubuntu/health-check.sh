#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/common.sh"
source "$SCRIPT_DIR/lib/env.sh"

ztg_parse_common_args "$@"
ztg_load_env

ztg_log_step "ZeroTier"
command -v zerotier-cli >/dev/null 2>&1 && zerotier-cli status || ztg_log_warn "zerotier-cli not found"
command -v zerotier-cli >/dev/null 2>&1 && zerotier-cli listnetworks || true
command -v zerotier-cli >/dev/null 2>&1 && zerotier-cli peers || true

ztg_log_step "Proxy"
if command -v ss >/dev/null 2>&1; then
  ss -lntp | grep ":${PROXY_PORT}" || ztg_log_warn "Proxy port ${PROXY_PORT} is not listening"
else
  ztg_log_warn "ss command not found"
fi

ztg_log_step "Service"
command -v systemctl >/dev/null 2>&1 && systemctl status sing-box-zt-proxy.service --no-pager || true
