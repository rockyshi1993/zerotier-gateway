#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/common.sh"
source "$SCRIPT_DIR/lib/env.sh"
source "$SCRIPT_DIR/lib/validate.sh"
source "$SCRIPT_DIR/lib/template.sh"
source "$SCRIPT_DIR/lib/sing-box.sh"
source "$SCRIPT_DIR/lib/firewall.sh"
source "$SCRIPT_DIR/lib/systemd.sh"

ztg_parse_common_args "$@"
ztg_load_env
ztg_validate_proxy_config
ztg_require_root
ztg_ensure_artifacts

ztg_install_sing_box
ztg_render_sing_box_config
ztg_apply_firewall_proxy
ztg_install_systemd_unit "$ZTG_ROOT/templates/systemd/sing-box-zt-proxy.service.tmpl" "sing-box-zt-proxy.service"
ztg_run install -d -m 0755 /etc/zerotier-gateway
ztg_run cp "$ZTG_ARTIFACTS_DIR/sing-box-server.json" /etc/zerotier-gateway/sing-box-server.json
ztg_run systemctl restart sing-box-zt-proxy.service
ztg_log_info "Proxy should listen on ${PROXY_BIND_IP}:${PROXY_PORT}."
ztg_log_info "Client proxy entry should use ${PROXY_CONNECT_HOST}:${PROXY_PORT}."
