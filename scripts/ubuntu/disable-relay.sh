#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/common.sh"
source "$SCRIPT_DIR/lib/env.sh"

ztg_parse_common_args "$@"
ztg_load_env
ztg_require_root

ztg_log_step "Disable optional relay"
ztg_run systemctl disable --now zerotier-tcp-relay.service
ztg_log_info "Relay disabled. ZeroTier DIRECT remains preferred."
