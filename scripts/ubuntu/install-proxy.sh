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

ztg_install_proxy_args=()
for ztg_arg in "$@"; do
  case "$ztg_arg" in
    --allow-zerotier-udp) ZTG_ALLOW_ZEROTIER_UDP_FLAG=true ;;
    *) ztg_install_proxy_args+=("$ztg_arg") ;;
  esac
done
ztg_parse_common_args "${ztg_install_proxy_args[@]+"${ztg_install_proxy_args[@]}"}"
ztg_load_env
# --allow-zerotier-udp overrides ZEROTIER_ALLOW_UDP_INBOUND from .env (opt-in, default off).
if [ "${ZTG_ALLOW_ZEROTIER_UDP_FLAG:-false}" = "true" ]; then
  ZEROTIER_ALLOW_UDP_INBOUND=true
fi
ztg_validate_proxy_config
ztg_require_root
ztg_ensure_artifacts

ztg_install_sing_box
ztg_render_sing_box_config
ztg_apply_firewall_proxy
ztg_apply_firewall_zerotier_udp
ztg_install_systemd_unit "$ZTG_ROOT/templates/systemd/sing-box-zt-proxy.service.tmpl" "sing-box-zt-proxy.service"
ztg_run install -d -m 0755 /etc/zerotier-gateway
ztg_run cp "$ZTG_ARTIFACTS_DIR/sing-box-server.json" /etc/zerotier-gateway/sing-box-server.json
ztg_run systemctl restart sing-box-zt-proxy.service
ztg_log_info "Proxy should listen on ${PROXY_BIND_IP}:${PROXY_PORT}."
ztg_log_info "Client proxy entry should use ${PROXY_CONNECT_HOST}:${PROXY_PORT}."
