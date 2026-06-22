#!/usr/bin/env bash

ztg_install_zerotier() {
  if command -v zerotier-cli >/dev/null 2>&1; then
    ztg_log_info "ZeroTier is already installed."
    return 0
  fi
  ztg_log_step "Install ZeroTier One"
  ztg_run sh -c 'curl -s https://install.zerotier.com | bash'
}

ztg_join_network() {
  ztg_log_step "Join ZeroTier network ${ZEROTIER_NETWORK_ID}"
  ztg_run zerotier-cli join "$ZEROTIER_NETWORK_ID"
  ztg_log_info "Authorize this node in ZeroTier Central and assign ${UBUNTU_ZT_IP}."
}

ztg_set_network_flags() {
  ztg_log_step "Set ZeroTier client flags"
  ztg_run zerotier-cli set "$ZEROTIER_NETWORK_ID" allowManaged=1
  ztg_run zerotier-cli set "$ZEROTIER_NETWORK_ID" allowGlobal=0
  ztg_run zerotier-cli set "$ZEROTIER_NETWORK_ID" allowDefault=0
  ztg_run zerotier-cli set "$ZEROTIER_NETWORK_ID" allowDNS=0
}
