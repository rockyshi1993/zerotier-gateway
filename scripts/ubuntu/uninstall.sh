#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/common.sh"
source "$SCRIPT_DIR/lib/env.sh"

ztg_parse_common_args "$@"
ztg_load_env
ztg_require_root

ztg_log_step "Remove ZeroTier Gateway managed services"
ztg_run systemctl disable --now sing-box-zt-proxy.service
ztg_run rm -f /etc/systemd/system/sing-box-zt-proxy.service
ztg_run systemctl daemon-reload
ztg_log_info "ZeroTier itself was not removed."
