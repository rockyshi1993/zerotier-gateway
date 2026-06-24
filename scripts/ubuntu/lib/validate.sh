#!/usr/bin/env bash

ztg_validate_network_id() {
  if ! [[ "${ZEROTIER_NETWORK_ID:-}" =~ ^[0-9a-fA-F]{16}$ ]]; then
    ztg_log_error "ZEROTIER_NETWORK_ID must be a 16-character hex value."
    exit 1
  fi
}

ztg_validate_proxy_config() {
  if [ "${PROXY_BIND_IP:-}" = "0.0.0.0" ] && ! ztg_is_true "${PROXY_PUBLIC_ACCESS:-false}"; then
    ztg_log_error "PROXY_BIND_IP=0.0.0.0 is only allowed when PROXY_PUBLIC_ACCESS=true."
    ztg_log_error "Default private mode should use the Ubuntu ZeroTier IP, for example ${UBUNTU_ZT_IP:-10.246.77.1}."
    exit 1
  fi
  if { [ -n "${PROXY_USERNAME:-}" ] && [ -z "${PROXY_PASSWORD:-}" ]; } || \
     { [ -z "${PROXY_USERNAME:-}" ] && [ -n "${PROXY_PASSWORD:-}" ]; }; then
    ztg_log_error "PROXY_USERNAME and PROXY_PASSWORD must be set together, or both left empty to disable proxy authentication."
    exit 1
  fi
  if ztg_is_true "${PROXY_PUBLIC_ACCESS:-false}"; then
    if [ -z "${PROXY_CONNECT_HOST:-}" ] || [ "${PROXY_CONNECT_HOST:-}" = "${UBUNTU_ZT_IP:-}" ]; then
      ztg_log_warn "PROXY_PUBLIC_ACCESS=true but PROXY_CONNECT_HOST still points to the ZeroTier private IP. This is OK for joined ZeroTier clients; non-ZeroTier clients need the server public IP."
    fi
    if [ -z "${PROXY_ALLOWED_CLIENT_CIDRS:-}" ]; then
      ztg_log_warn "PROXY_PUBLIC_ACCESS=true and PROXY_ALLOWED_CLIENT_CIDRS is empty. Public proxy access will allow all source IPs unless another firewall restricts it."
    fi
    if [ -z "${PROXY_USERNAME:-}" ] && [ -z "${PROXY_PASSWORD:-}" ]; then
      ztg_log_warn "Proxy authentication is disabled. This is allowed, but all-source public access can be abused if exposed to the Internet."
    fi
  fi
}

ztg_validate_all() {
  ztg_validate_network_id
  ztg_validate_proxy_config
}
