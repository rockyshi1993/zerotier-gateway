#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/common.sh"
source "$SCRIPT_DIR/lib/env.sh"
source "$SCRIPT_DIR/lib/validate.sh"
source "$SCRIPT_DIR/lib/zerotier.sh"

ztg_parse_common_args "$@"
ztg_load_env
ztg_validate_network_id
ztg_require_root

ztg_install_zerotier
ztg_join_network
ztg_set_network_flags
ztg_log_info "Next: authorize the node in ZeroTier Central and assign ${UBUNTU_ZT_IP}."
