#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/common.sh"
source "$SCRIPT_DIR/lib/env.sh"
source "$SCRIPT_DIR/lib/relay.sh"

ztg_parse_common_args "$@"
ztg_load_env
ztg_require_root
ztg_relay_preview

if [ "$ZTG_DRY_RUN" = "true" ]; then
  ztg_log_info "Dry-run complete. No relay service was installed."
  exit 0
fi

ztg_log_warn "Relay binary installation is environment-specific."
ztg_log_warn "Install a compatible ZeroTier TCP relay, then use templates/systemd/zerotier-tcp-relay.service.tmpl."
