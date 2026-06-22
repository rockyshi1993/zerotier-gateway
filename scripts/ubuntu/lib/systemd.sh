#!/usr/bin/env bash

ztg_install_systemd_unit() {
  local template="$1"
  local unit_name="$2"
  local target="/etc/systemd/system/$unit_name"
  ztg_log_step "Install systemd unit $unit_name"
  if [ "${ZTG_DRY_RUN:-false}" = "true" ]; then
    ztg_log_info "Would render $template to $target"
    return 0
  fi
  ztg_render_template "$template" "$target"
  systemctl daemon-reload
  systemctl enable "$unit_name"
}
