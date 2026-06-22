#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/common.sh"
source "$SCRIPT_DIR/lib/env.sh"
source "$SCRIPT_DIR/lib/validate.sh"

ztg_parse_common_args "$@"
ztg_load_env
ztg_validate_all

ztg_log_step "ZeroTier Gateway install plan"
ztg_log_info "Config: $ZTG_ENV_FILE"
ztg_log_info "Network: $ZEROTIER_NETWORK_ID ($ZEROTIER_SUBNET)"
ztg_log_info "Proxy: ${PROXY_BIND_IP}:${PROXY_PORT}"

if [ "$ZTG_DRY_RUN" = "true" ]; then
  ztg_log_info "Dry-run complete. No system changes were made."
  exit 0
fi

ztg_require_root
bash "$SCRIPT_DIR/install-zerotier.sh" --env "$ZTG_ENV_FILE"
bash "$SCRIPT_DIR/install-proxy.sh" --env "$ZTG_ENV_FILE"
ztg_log_info "Install finished. Authorize devices in ZeroTier Central, then run health-check.sh."
