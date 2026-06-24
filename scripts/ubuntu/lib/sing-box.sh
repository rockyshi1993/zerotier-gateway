#!/usr/bin/env bash

ztg_install_sing_box() {
  if command -v sing-box >/dev/null 2>&1; then
    ztg_log_info "sing-box is already installed."
    return 0
  fi

  ztg_log_step "Install sing-box"
  if command -v apt-get >/dev/null 2>&1; then
    ztg_run apt-get update
    if [ "${ZTG_DRY_RUN:-false}" != "true" ] && ! apt-cache show sing-box >/dev/null 2>&1; then
      ztg_configure_sagernet_apt_repo
      ztg_run apt-get update
    fi
    ztg_run apt-get install -y sing-box
  elif command -v dnf >/dev/null 2>&1; then
    ztg_run dnf install -y sing-box
  elif command -v yum >/dev/null 2>&1; then
    ztg_run yum install -y sing-box
  else
    ztg_log_warn "No supported package manager found. Install sing-box manually, then rerun."
  fi
}

ztg_configure_sagernet_apt_repo() {
  ztg_log_info "sing-box is not available in current apt sources; add the official SagerNet apt repository."
  ztg_run apt-get install -y curl ca-certificates
  ztg_run install -d -m 0755 /etc/apt/keyrings
  ztg_run curl -fsSL https://sing-box.app/gpg.key -o /etc/apt/keyrings/sagernet.asc
  ztg_run chmod a+r /etc/apt/keyrings/sagernet.asc
  ztg_write_sagernet_sources
}

ztg_write_sagernet_sources() {
  if [ "${ZTG_DRY_RUN:-false}" = "true" ]; then
    printf '[DRY-RUN] write /etc/apt/sources.list.d/sagernet.sources\n'
    return 0
  fi

  cat > /etc/apt/sources.list.d/sagernet.sources <<'APT'
Types: deb
URIs: https://deb.sagernet.org/
Suites: *
Components: *
Enabled: yes
Signed-By: /etc/apt/keyrings/sagernet.asc
APT
}

ztg_json_escape() {
  local value="$1"
  value="${value//\\/\\\\}"
  value="${value//\"/\\\"}"
  value="${value//$'\n'/\\n}"
  value="${value//$'\r'/\\r}"
  value="${value//$'\t'/\\t}"
  printf '%s' "$value"
}

ztg_build_server_auth_json() {
  if [ -z "${PROXY_USERNAME:-}" ] && [ -z "${PROXY_PASSWORD:-}" ]; then
    return 0
  fi

  local username password
  username="$(ztg_json_escape "$PROXY_USERNAME")"
  password="$(ztg_json_escape "$PROXY_PASSWORD")"
  printf ',"users":[{"username":"%s","password":"%s"}]' "$username" "$password"
}

ztg_render_sing_box_config() {
  ztg_log_step "Render sing-box config"
  local target="${1:-$ZTG_ARTIFACTS_DIR/sing-box-server.json}"
  local SERVER_AUTH_JSON
  SERVER_AUTH_JSON="$(ztg_build_server_auth_json)"
  ztg_render_template "$ZTG_ROOT/templates/sing-box/server-mixed.json.tmpl" "$target"
  ztg_log_info "Rendered: $target"
}
