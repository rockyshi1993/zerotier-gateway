#!/usr/bin/env bash

ZTG_CADDY_USER="${ZTG_CADDY_USER:-zerotier-gateway-caddy}"

ztg_validate_domain_name() {
  local value="${1:-}"
  [ "${#value}" -le 253 ] && [[ "$value" =~ ^([a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?\.)+[a-z][a-z0-9-]{1,62}$ ]]
}

ztg_domain_state_path() {
  printf '%s/publish-domain-%s.json' "$(ztg_state_root)" "$1"
}

ztg_caddy_config_root() {
  printf '%s' "${ZTG_CADDY_CONFIG_ROOT:-/etc/zerotier-gateway/caddy}"
}

ztg_caddy_data_root() {
  printf '%s' "${ZTG_CADDY_DATA_ROOT:-/var/lib/zerotier-gateway/caddy}"
}

ztg_caddy_firewall_state_path() {
  printf '%s/caddy-firewall.json' "$(ztg_state_root)"
}

ztg_caddy_dependencies() {
  local file="${ZTG_DEPENDENCIES_FILE:-$ZTG_ROOT/config/dependencies.env}"
  [ -f "$file" ] || { ztg_log_error "Dependency manifest not found: $file"; return 1; }
  CADDY_VERSION="$(awk -F= '$1=="CADDY_VERSION"{print $2}' "$file")"
  CADDY_LINUX_AMD64_SHA512="$(awk -F= '$1=="CADDY_LINUX_AMD64_SHA512"{print $2}' "$file")"
  CADDY_LINUX_ARM64_SHA512="$(awk -F= '$1=="CADDY_LINUX_ARM64_SHA512"{print $2}' "$file")"
  [ -n "$CADDY_VERSION" ] && [ -n "$CADDY_LINUX_AMD64_SHA512" ] && [ -n "$CADDY_LINUX_ARM64_SHA512" ]
}

ztg_caddy_arch() {
  case "$(uname -m)" in
    x86_64|amd64) printf 'amd64' ;;
    aarch64|arm64) printf 'arm64' ;;
    *) ztg_log_error "Unsupported Caddy architecture: $(uname -m)"; return 1 ;;
  esac
}

ztg_caddy_binary_path() {
  ztg_caddy_dependencies || return 1
  printf '%s/caddy/%s/caddy' "${ZTG_OPT_ROOT:-/opt/zerotier-gateway}" "$CADDY_VERSION"
}

ztg_caddy_expected_sha512() {
  ztg_caddy_dependencies || return 1
  case "$1" in amd64) printf '%s' "$CADDY_LINUX_AMD64_SHA512" ;; arm64) printf '%s' "$CADDY_LINUX_ARM64_SHA512" ;; *) return 1 ;; esac
}

ztg_install_caddy_binary() {
  local arch expected target directory temporary archive extracted actual url binary_checksum checksum_file
  arch="$(ztg_caddy_arch)"; expected="$(ztg_caddy_expected_sha512 "$arch")"; target="$(ztg_caddy_binary_path)"; directory="$(dirname "$target")"
  checksum_file="$target.sha512"
  if [ -x "$target" ]; then
    [ -f "$checksum_file" ] || { ztg_log_error "Existing project Caddy checksum record is missing: $checksum_file"; return 1; }
    actual="$(sha512sum "$target" | awk '{print $1}')"
    [ "$actual" = "$(<"$checksum_file")" ] || { ztg_log_error "Existing project Caddy binary checksum mismatch: $target"; return 1; }
    "$target" version | grep -Fq "v${CADDY_VERSION}" || { ztg_log_error "Existing project Caddy version mismatch: $target"; return 1; }
    printf '%s' "$target"; return 0
  fi
  command -v curl >/dev/null && command -v tar >/dev/null && command -v sha512sum >/dev/null || { ztg_log_error 'curl, tar, and sha512sum are required.'; return 1; }
  temporary="$(mktemp -d)" || return 1
  archive="$temporary/caddy.tar.gz"; extracted="$temporary/caddy"
  url="https://github.com/caddyserver/caddy/releases/download/v${CADDY_VERSION}/caddy_${CADDY_VERSION}_linux_${arch}.tar.gz"
  ztg_log_info "Downloading official Caddy v${CADDY_VERSION} for linux/${arch}." >&2
  if ! curl --fail --location --silent --show-error "$url" --output "$archive"; then rm -rf "$temporary"; return 1; fi
  actual="$(sha512sum "$archive" | awk '{print $1}')"
  if [ "$actual" != "$expected" ]; then rm -rf "$temporary"; ztg_log_error 'Downloaded Caddy archive checksum mismatch.'; return 1; fi
  if ! tar -xzf "$archive" -C "$temporary" caddy; then rm -rf "$temporary"; return 1; fi
  binary_checksum="$(sha512sum "$extracted" | awk '{print $1}')"
  mkdir -p "$directory"; install -m 0755 "$extracted" "$target"; printf '%s\n' "$binary_checksum" > "$checksum_file"; chmod 0644 "$checksum_file"; rm -rf "$temporary"
  "$target" version >/dev/null
  printf '%s' "$target"
}

ztg_render_caddy_site() {
  local name="$1" domain="$2" target_ip="$3" target_port="$4" staging="$5" auth_user="$6" auth_hash="$7" source_cidr="${8:-}"
  printf '# Managed-By: zerotier-gateway-domain-%s\n' "$name"
  printf '%s {\n' "$domain"
  printf '  route {\n'
  if [ -n "$source_cidr" ]; then
    printf '    @outsideAllowedSource {\n      not remote_ip %s\n    }\n' "$source_cidr"
    printf '    respond @outsideAllowedSource 403\n'
  fi
  if [ -n "$auth_user" ]; then
    printf '    basic_auth {\n      %s %s\n    }\n' "$auth_user" "$auth_hash"
  fi
  printf '    reverse_proxy %s:%s\n' "$target_ip" "$target_port"
  printf '  }\n'
  if [ "$staging" = true ]; then
    printf '  tls {\n    ca https://acme-staging-v02.api.letsencrypt.org/directory\n  }\n'
  fi
  printf '}\n'
}

ztg_render_caddy_main() {
  cat <<'CADDY'
# Managed-By: zerotier-gateway-caddy
{
  admin 127.0.0.1:2019
}

import sites/*.caddy
CADDY
}

ztg_render_caddy_service() {
  local binary="$1" config_root="$2" data_root="$3"
  local template content
  template="$(<"$ZTG_ROOT/templates/systemd/zerotier-gateway-caddy.service.tmpl")"
  content="${template//\{\{CADDY_BINARY\}\}/$binary}"
  content="${content//\{\{CADDY_CONFIG_ROOT\}\}/$config_root}"
  content="${content//\{\{CADDY_DATA_ROOT\}\}/$data_root}"
  content="${content//\{\{CADDY_USER\}\}/$ZTG_CADDY_USER}"
  printf '%s\n' "$content"
}

ztg_write_domain_state() {
  local path="$1" name="$2" domain="$3" target_ip="$4" target_port="$5" staging="$6" auth_user="$7" auth_hash="$8" source_cidr="$9" generation="${10}"
  local json
  json=$(cat <<JSON
{
  "schemaVersion": ${ZTG_STATE_SCHEMA_VERSION},
  "objectVersion": 1,
  "owner": "${ZTG_STATE_OWNER}",
  "objectType": "publish-domain",
  "objectName": "$(ztg_json_escape "$name")",
  "enabled": true,
  "lastAppliedVersion": "$(ztg_json_escape "$(ztg_project_version)")",
  "generation": ${generation},
  "domain": "$(ztg_json_escape "$domain")",
  "targetIp": "$(ztg_json_escape "$target_ip")",
  "targetPort": "$(ztg_json_escape "$target_port")",
  "acmeStaging": ${staging},
  "basicAuthUser": "$(ztg_json_escape "$auth_user")",
  "basicAuthHash": "$(ztg_json_escape "$auth_hash")",
  "sourceCidr": "$(ztg_json_escape "$source_cidr")",
  "updatedAt": "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
}
JSON
)
  ztg_atomic_write "$path" "$json" 0600
}

ztg_write_caddy_firewall_state() {
  local path="$1" generation="$2" json
  json=$(cat <<JSON
{
  "schemaVersion": ${ZTG_STATE_SCHEMA_VERSION},
  "objectVersion": 1,
  "owner": "${ZTG_STATE_OWNER}",
  "objectType": "publish-firewall",
  "objectName": "caddy",
  "enabled": true,
  "lastAppliedVersion": "$(ztg_json_escape "$(ztg_project_version)")",
  "generation": ${generation},
  "firewallMode": "ufw",
  "httpMarker": "$(ztg_publish_marker caddy-http)",
  "httpsMarker": "$(ztg_publish_marker caddy-https)",
  "updatedAt": "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
}
JSON
)
  ztg_atomic_write "$path" "$json" 0600
}

ztg_caddy_firewall_state_owned() {
  local path="$1"
  ztg_validate_state_identity "$path" publish-firewall caddy
}

ztg_caddy_unit_owned() {
  local path="$1"
  [ -f "$path" ] && grep -Fqx '# Managed-By: zerotier-gateway-caddy' "$path"
}

ztg_assert_caddy_config_owned() {
  local root="$1" file entry
  [ -e "$root" ] || return 0
  if [ -f "$root/Caddyfile" ]; then
    grep -Fqx '# Managed-By: zerotier-gateway-caddy' "$root/Caddyfile" || { ztg_log_error "Caddyfile is not project-owned: $root/Caddyfile"; return 1; }
  elif find "$root" -mindepth 1 -print -quit 2>/dev/null | grep -q .; then
    ztg_log_error "Non-empty Caddy config directory has no project ownership marker: $root"
    return 1
  fi
  for entry in "$root"/*; do
    [ -e "$entry" ] || continue
    case "$(basename "$entry")" in Caddyfile|sites) ;; *) ztg_log_error "Unexpected file in project Caddy config root: $entry"; return 1 ;; esac
  done
  for file in "$root/sites/"*.caddy; do
    [ -f "$file" ] || continue
    grep -Eq '^# Managed-By: zerotier-gateway-domain-[A-Za-z0-9_-]+$' "$file" || { ztg_log_error "Domain config is not project-owned: $file"; return 1; }
  done
  for entry in "$root/sites/"*; do
    [ -e "$entry" ] || continue
    [[ "$entry" == *.caddy ]] || { ztg_log_error "Unexpected file in project Caddy sites directory: $entry"; return 1; }
  done
}

ztg_count_domain_states() {
  local count=0 file
  for file in "$(ztg_state_root)"/publish-domain-*.json; do [ -f "$file" ] && count=$((count + 1)); done
  printf '%s' "$count"
}

ztg_domain_in_use() {
  local domain="$1" exclude_name="${2:-}" file state_name expected_name
  for file in "$(ztg_state_root)"/publish-domain-*.json; do
    [ -f "$file" ] || continue
    expected_name="$(basename "$file")"; expected_name="${expected_name#publish-domain-}"; expected_name="${expected_name%.json}"
    ztg_validate_state_identity "$file" publish-domain "$expected_name" || return 2
    state_name="$(ztg_read_json_scalar "$file" objectName)"
    [ "$state_name" = "$exclude_name" ] && continue
    [ "$(ztg_read_json_scalar "$file" domain)" = "$domain" ] && return 0
  done
  return 1
}
