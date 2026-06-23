#!/usr/bin/env bash

ztg_validate_network_id() {
  if ! [[ "${ZEROTIER_NETWORK_ID:-}" =~ ^[0-9a-fA-F]{16}$ ]]; then
    ztg_log_error "ZEROTIER_NETWORK_ID must be a 16-character hex value."
    exit 1
  fi
}

ztg_validate_proxy_config() {
  if [ "${PROXY_BIND_IP:-}" = "0.0.0.0" ]; then
    ztg_log_error "PROXY_BIND_IP must not be 0.0.0.0. Use the Ubuntu ZeroTier IP."
    exit 1
  fi
  if { [ -n "${PROXY_USERNAME:-}" ] && [ -z "${PROXY_PASSWORD:-}" ]; } || \
     { [ -z "${PROXY_USERNAME:-}" ] && [ -n "${PROXY_PASSWORD:-}" ]; }; then
    ztg_log_error "PROXY_USERNAME and PROXY_PASSWORD must be set together, or both left empty to disable proxy authentication."
    exit 1
  fi
}

ztg_validate_all() {
  ztg_validate_network_id
  ztg_validate_proxy_config
}
