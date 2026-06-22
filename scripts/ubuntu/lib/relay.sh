#!/usr/bin/env bash

ztg_relay_preview() {
  ztg_log_step "Relay preview"
  ztg_log_info "Relay is optional and should be enabled only when DIRECT is poor."
  ztg_log_info "Configured relay port: ${RELAY_PORT}"
}
