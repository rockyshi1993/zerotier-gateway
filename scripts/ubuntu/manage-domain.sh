#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/common.sh"
source "$SCRIPT_DIR/lib/state.sh"
source "$SCRIPT_DIR/lib/rate-limit.sh"
source "$SCRIPT_DIR/lib/publish.sh"
source "$SCRIPT_DIR/lib/caddy.sh"

usage() {
  cat <<'HELP'
Publish a ZeroTier HTTP site with a real domain and automatic HTTPS; no file editing is required.

Usage:
  manage-publish.sh add-domain|update-domain [options] [--apply]
  manage-publish.sh list-domains
  manage-publish.sh status-domain|test-domain --name NAME
  manage-publish.sh remove-domain --name NAME [--apply]

Options:
  --name NAME                 Mapping name.
  --domain HOSTNAME           Public domain; DNS must already resolve.
  --target-ip ZT_IP           ZeroTier web-server address.
  --target-port PORT          HTTP target port.
  --zerotier-subnet CIDR      Target validation subnet. Default: 10.246.77.0/24.
  --expected-public-ip IP     Optional DNS result assertion.
  --staging                   Use Let's Encrypt staging for this domain.
  --production                Switch an existing staging domain to production ACME.
  --source-cidr CIDR          Optional application-layer source restriction.
  --basic-auth-user USER      Prompt for a password and generate a Caddy hash during Apply.
  --clear-basic-auth          Remove existing basic authentication.
  --apply                     Download/validate/apply. Without it, no system change occurs.
HELP
}

[ "$#" -gt 0 ] || { usage; exit 2; }
action="$1"; shift
case "$action" in add-domain|update-domain|list-domains|status-domain|test-domain|remove-domain) ;; *) usage; exit 2 ;; esac

name='' domain='' target_ip='' target_port='' zerotier_subnet='10.246.77.0/24' expected_public_ip='' staging=false source_cidr='' auth_user='' clear_auth=false apply=false
has_domain=false; has_target_ip=false; has_target_port=false; has_staging=false; has_source_cidr=false; has_auth=false
while [ "$#" -gt 0 ]; do
  case "$1" in
    --name) name="${2:-}"; shift 2 ;;
    --domain) domain="$(printf '%s' "${2:-}" | tr '[:upper:]' '[:lower:]')"; has_domain=true; shift 2 ;;
    --target-ip) target_ip="${2:-}"; has_target_ip=true; shift 2 ;;
    --target-port) target_port="${2:-}"; has_target_port=true; shift 2 ;;
    --zerotier-subnet) zerotier_subnet="${2:-}"; shift 2 ;;
    --expected-public-ip) expected_public_ip="${2:-}"; shift 2 ;;
    --staging) staging=true; has_staging=true; shift ;;
    --production) staging=false; has_staging=true; shift ;;
    --source-cidr) source_cidr="${2:-}"; has_source_cidr=true; shift 2 ;;
    --basic-auth-user) auth_user="${2:-}"; has_auth=true; shift 2 ;;
    --clear-basic-auth) clear_auth=true; has_auth=true; shift ;;
    --apply) apply=true; shift ;;
    -h|--help) usage; exit 0 ;;
    *) ztg_log_error "Unknown argument: $1"; usage; exit 2 ;;
  esac
done

state_root="$(ztg_state_root)"; config_root="$(ztg_caddy_config_root)"; data_root="$(ztg_caddy_data_root)"; firewall_state_path="$(ztg_caddy_firewall_state_path)"
unit_dir="${ZTG_SYSTEMD_DIR:-/etc/systemd/system}"; unit_path="$unit_dir/zerotier-gateway-caddy.service"

require_name() {
  if [ -z "$name" ] && [ -t 0 ]; then read -r -p 'Domain mapping name: ' name; fi
  ztg_validate_publish_name "$name" || { ztg_log_error 'A valid --name is required.'; exit 2; }
}

load_state() {
  local path="$1"
  [ -f "$path" ] || { ztg_log_error "Domain mapping not found: $name"; exit 1; }
  ztg_validate_state_identity "$path" publish-domain "$name" || exit 1
  domain="$(ztg_read_json_scalar "$path" domain)"; target_ip="$(ztg_read_json_scalar "$path" targetIp)"; target_port="$(ztg_read_json_scalar "$path" targetPort)"
  staging="$(ztg_json_boolean "$path" acmeStaging)"; source_cidr="$(ztg_read_json_scalar "$path" sourceCidr)"; auth_user="$(ztg_read_json_scalar "$path" basicAuthUser)"; auth_hash="$(ztg_read_json_scalar "$path" basicAuthHash)"
  generation="$(sed -nE 's/^[[:space:]]*"generation"[[:space:]]*:[[:space:]]*([0-9]+).*/\1/p' "$path" | head -n 1)"
}

render_candidate() {
  local directory="$1" replacement_name="$2" replacement_site="$3" exclude_name="${4:-}" file state_name
  mkdir -p "$directory/sites"; ztg_render_caddy_main > "$directory/Caddyfile"
  for file in "$state_root"/publish-domain-*.json; do
    [ -f "$file" ] || continue
    state_name="$(basename "$file")"; state_name="${state_name#publish-domain-}"; state_name="${state_name%.json}"
    ztg_validate_publish_name "$state_name" || { ztg_log_error "Invalid domain state name: $file"; return 1; }
    ztg_validate_state_identity "$file" publish-domain "$state_name" || return 1
    [ "$state_name" = "$replacement_name" ] && continue; [ "$state_name" = "$exclude_name" ] && continue
    ztg_render_caddy_site "$state_name" "$(ztg_read_json_scalar "$file" domain)" "$(ztg_read_json_scalar "$file" targetIp)" "$(ztg_read_json_scalar "$file" targetPort)" \
      "$(ztg_json_boolean "$file" acmeStaging)" "$(ztg_read_json_scalar "$file" basicAuthUser)" "$(ztg_read_json_scalar "$file" basicAuthHash)" "$(ztg_read_json_scalar "$file" sourceCidr)" > "$directory/sites/$state_name.caddy"
  done
  if [ -n "$replacement_name" ]; then printf '%s\n' "$replacement_site" > "$directory/sites/$replacement_name.caddy"; fi
}

if [ "$action" = list-domains ]; then
  found=false
  for file in "$state_root"/publish-domain-*.json; do
    [ -f "$file" ] || continue; found=true
    state_name="$(basename "$file")"; state_name="${state_name#publish-domain-}"; state_name="${state_name%.json}"
    ztg_validate_state_identity "$file" publish-domain "$state_name" || exit 1
    printf '%-20s https://%-35s -> %s:%s\n' \
    "$(ztg_read_json_scalar "$file" objectName)" "$(ztg_read_json_scalar "$file" domain)" "$(ztg_read_json_scalar "$file" targetIp)" "$(ztg_read_json_scalar "$file" targetPort)"; done
  $found || ztg_log_warn 'No domain mappings are configured.'; exit 0
fi

require_name; state_path="$(ztg_domain_state_path "$name")"
case "$action" in
  add-domain|update-domain|remove-domain)
    if [ "$apply" = true ]; then
      ztg_require_root
      ztg_acquire_management_lock
      trap 'ztg_release_management_lock' EXIT
    fi
    ;;
esac

case "$action" in
  add-domain|update-domain)
    exists=false; requested_domain="$domain"; requested_target_ip="$target_ip"; requested_target_port="$target_port"; requested_staging="$staging"; requested_source_cidr="$source_cidr"; requested_auth_user="$auth_user"
    if [ -f "$state_path" ]; then
      exists=true; load_state "$state_path"; old_state="$(<"$state_path")"
      $has_domain && domain="$requested_domain"; $has_target_ip && target_ip="$requested_target_ip"; $has_target_port && target_port="$requested_target_port"
      $has_staging && staging="$requested_staging"
      $has_source_cidr && source_cidr="$requested_source_cidr"
      if $has_auth; then if $clear_auth; then auth_user=''; auth_hash=''; else auth_user="$requested_auth_user"; auth_hash='__GENERATE__'; fi; fi
    else
      domain="$requested_domain"; target_ip="$requested_target_ip"; target_port="$requested_target_port"; staging="$requested_staging"; source_cidr="$requested_source_cidr"; auth_user="$requested_auth_user"; auth_hash=''
      $has_auth && ! $clear_auth && auth_hash='__GENERATE__'; generation=1; old_state=''
    fi
    if [ "$action" = add-domain ] && $exists; then ztg_log_error "Domain mapping already exists: $name"; exit 1; fi
    if [ "$action" = update-domain ] && ! $exists; then ztg_log_error "Domain mapping not found: $name"; exit 1; fi
    if [ -t 0 ]; then [ -n "$domain" ] || read -r -p 'Public domain: ' domain; [ -n "$target_ip" ] || read -r -p 'ZeroTier target IP: ' target_ip; [ -n "$target_port" ] || read -r -p 'HTTP target port: ' target_port; fi
    ztg_validate_domain_name "$domain" || { ztg_log_error 'Invalid public domain name.'; exit 2; }
    if ztg_domain_in_use "$domain" "$name"; then
      ztg_log_error "Domain is already managed by another mapping: $domain"
      exit 1
    else
      domain_lookup_rc=$?
      [ "$domain_lookup_rc" -eq 1 ] || exit "$domain_lookup_rc"
    fi
    ztg_validate_ipv4_cidr "$target_ip" && [[ "$target_ip" != */* ]] || { ztg_log_error 'Invalid target IPv4 address.'; exit 2; }
    ztg_ipv4_in_cidr "$target_ip" "$zerotier_subnet" || { ztg_log_error "$target_ip is outside ZeroTier subnet $zerotier_subnet."; exit 1; }
    ztg_validate_proxy_port "$target_port" || { ztg_log_error 'Invalid target port.'; exit 2; }
    if [ -n "$expected_public_ip" ]; then ztg_validate_ipv4_cidr "$expected_public_ip" && [[ "$expected_public_ip" != */* ]] || { ztg_log_error 'Invalid expected public IPv4 address.'; exit 2; }; fi
    if [ -n "$source_cidr" ]; then ztg_validate_ipv4_cidr "$source_cidr" || { ztg_log_error 'Invalid source CIDR.'; exit 2; }; fi
    [[ "$auth_user" =~ ^[A-Za-z0-9._@-]{0,64}$ ]] || { ztg_log_error 'Invalid basic-auth user.'; exit 2; }
    if ! $exists && [ "$(ztg_count_domain_states)" -ge 64 ]; then ztg_log_error 'The 64-domain first-release capacity has been reached.'; exit 1; fi
    ztg_log_info "Plan: $action $name; https://$domain -> http://${target_ip}:${target_port}; staging=$staging; source=${source_cidr:-any}; basic-auth=$(if [ -n "$auth_user" ]; then printf enabled; else printf disabled; fi)"
    if [ "$apply" != true ]; then ztg_log_warn 'Preview only. Re-run with --apply after DNS points to this server and ports 80/443 are reachable.'; exit 0; fi
    ztg_require_root; command -v systemctl >/dev/null || { ztg_log_error 'systemctl is required.'; exit 1; }
    command -v getent >/dev/null && command -v timeout >/dev/null && command -v curl >/dev/null || { ztg_log_error 'getent, timeout, and curl are required.'; exit 1; }
    dns_ips="$(getent ahostsv4 "$domain" 2>/dev/null | awk '{print $1}' | sort -u)"
    [ -n "$dns_ips" ] || { ztg_log_error "DNS has no IPv4 result for $domain."; exit 1; }
    if [ -n "$expected_public_ip" ]; then printf '%s\n' "$dns_ips" | grep -Fqx -- "$expected_public_ip" || { ztg_log_error "DNS does not include expected public IP $expected_public_ip."; exit 1; }; fi
    timeout 5 bash -c "</dev/tcp/$target_ip/$target_port" || { ztg_log_error 'ZeroTier HTTP target TCP check failed.'; exit 1; }
    if ! systemctl is-active --quiet zerotier-gateway-caddy.service 2>/dev/null; then
      ztg_publish_port_occupied 0.0.0.0 80 && { ztg_log_error 'TCP port 80 is already occupied by a non-project listener.'; exit 1; }
      ztg_publish_port_occupied 0.0.0.0 443 && { ztg_log_error 'TCP port 443 is already occupied by a non-project listener.'; exit 1; }
      ztg_publish_port_occupied 127.0.0.1 2019 && { ztg_log_error 'Caddy admin port 127.0.0.1:2019 is already occupied.'; exit 1; }
    elif ! ztg_caddy_unit_owned "$unit_path"; then ztg_log_error 'The active same-name Caddy unit is not project-owned.'; exit 1; fi
    binary="$(ztg_install_caddy_binary)" || exit 1
    if ! id "$ZTG_CADDY_USER" >/dev/null 2>&1; then useradd --system --home-dir "$data_root" --shell /usr/sbin/nologin "$ZTG_CADDY_USER"; fi
    mkdir -p "$data_root"; chown -R "$ZTG_CADDY_USER:$ZTG_CADDY_USER" "$data_root"
    if [ "$auth_hash" = '__GENERATE__' ]; then
      [ -t 0 ] || { ztg_log_error 'Basic-auth password prompting requires an interactive terminal.'; exit 1; }
      read -r -s -p 'Basic-auth password: ' auth_password; printf '\n'
      auth_hash="$("$binary" hash-password --plaintext "$auth_password")"; unset auth_password
    fi
    site="$(ztg_render_caddy_site "$name" "$domain" "$target_ip" "$target_port" "$staging" "$auth_user" "$auth_hash" "$source_cidr")"
    candidate="$(mktemp -d)"; backup="$(mktemp -d)"; trap 'rm -rf "$candidate" "$backup"' EXIT
    render_candidate "$candidate" "$name" "$site"
    "$binary" validate --config "$candidate/Caddyfile" --adapter caddyfile >/dev/null
    ztg_assert_caddy_config_owned "$config_root"
    config_existed=false; unit_existed=false; firewall_state_existed=false; old_firewall_state=''; firewall_generation=1
    if [ -d "$config_root" ]; then config_existed=true; cp -a "$config_root/." "$backup/config"; fi
    if [ -f "$unit_path" ]; then ztg_caddy_unit_owned "$unit_path" || { ztg_log_error 'Caddy unit ownership mismatch.'; exit 1; }; unit_existed=true; cp "$unit_path" "$backup/unit"; fi
    if [ -f "$firewall_state_path" ]; then
      ztg_caddy_firewall_state_owned "$firewall_state_path" || { ztg_log_error 'Caddy firewall state ownership mismatch.'; exit 1; }
      firewall_state_existed=true; old_firewall_state="$(<"$firewall_state_path")"
      firewall_generation="$(sed -nE 's/^[[:space:]]*"generation"[[:space:]]*:[[:space:]]*([0-9]+).*/\1/p' "$firewall_state_path" | head -n 1)"
      firewall_generation=$((firewall_generation + 1))
    fi
    deployment_failed=false
    mkdir -p "$config_root/sites" "$unit_dir" || deployment_failed=true
    if ! $deployment_failed; then rm -f "$config_root/sites/"*.caddy || deployment_failed=true; fi
    if ! $deployment_failed; then install -m 0640 "$candidate/Caddyfile" "$config_root/Caddyfile" || deployment_failed=true; fi
    if ! $deployment_failed; then
      for file in "$candidate/sites/"*.caddy; do install -m 0640 "$file" "$config_root/sites/$(basename "$file")" || { deployment_failed=true; break; }; done
    fi
    if ! $deployment_failed; then chown -R "root:$ZTG_CADDY_USER" "$config_root" || deployment_failed=true; fi
    if ! $deployment_failed; then ztg_render_caddy_service "$binary" "$config_root" "$data_root" > "$unit_path" && chmod 0644 "$unit_path" || deployment_failed=true; fi
    if $deployment_failed; then
      rm -rf "$config_root"
      if $config_existed; then mkdir -p "$config_root"; cp -a "$backup/config/." "$config_root"; fi
      if $unit_existed; then cp "$backup/unit" "$unit_path"; else rm -f "$unit_path"; fi
      ztg_log_error 'Caddy project-file deployment failed; prior files were restored and the running service was not reloaded.'
      exit 1
    fi
    caddy_http_added=false; caddy_https_added=false; firewall_failed=false
    firewall_managed=false
    if ztg_ufw_active; then
      if ! ztg_ufw_rule_numbers "$(ztg_publish_marker caddy-http)" | grep -q .; then ztg_add_owned_ufw_rule caddy-http 0.0.0.0 80 '' && caddy_http_added=true || firewall_failed=true; fi
      if ! ztg_ufw_rule_numbers "$(ztg_publish_marker caddy-https)" | grep -q .; then ztg_add_owned_ufw_rule caddy-https 0.0.0.0 443 '' && caddy_https_added=true || firewall_failed=true; fi
      if ! $firewall_failed; then
        ztg_ufw_rule_numbers "$(ztg_publish_marker caddy-http)" | grep -q . && ztg_ufw_rule_numbers "$(ztg_publish_marker caddy-https)" | grep -q . && firewall_managed=true
      fi
    else
      ztg_log_warn 'ufw is unavailable or inactive; no dormant rules were added. Open host/cloud TCP 80 and 443 separately.'
    fi
    if $exists; then generation=$((generation + 1)); else generation=1; fi
    firewall_state_failed=false
    if $firewall_managed; then ztg_write_caddy_firewall_state "$firewall_state_path" "$firewall_generation" || firewall_state_failed=true; fi
    if $firewall_failed || $firewall_state_failed || ! ztg_write_domain_state "$state_path" "$name" "$domain" "$target_ip" "$target_port" "$staging" "$auth_user" "$auth_hash" "$source_cidr" "$generation" || ! systemctl daemon-reload || ! systemctl enable --now zerotier-gateway-caddy.service || ! systemctl reload zerotier-gateway-caddy.service; then
      systemctl stop zerotier-gateway-caddy.service >/dev/null 2>&1 || true
      $caddy_http_added && ztg_remove_owned_ufw_rule "$(ztg_publish_marker caddy-http)" || true
      $caddy_https_added && ztg_remove_owned_ufw_rule "$(ztg_publish_marker caddy-https)" || true
      rm -rf "$config_root"; if $config_existed; then mkdir -p "$config_root"; cp -a "$backup/config/." "$config_root"; fi
      if $unit_existed; then cp "$backup/unit" "$unit_path"; else rm -f "$unit_path"; fi
      if $exists; then ztg_atomic_write "$state_path" "$old_state" 0600; else rm -f "$state_path"; fi
      if $firewall_state_existed; then ztg_atomic_write "$firewall_state_path" "$old_firewall_state" 0600; else rm -f "$firewall_state_path"; fi
      systemctl daemon-reload >/dev/null 2>&1 || true; if $unit_existed; then systemctl enable --now zerotier-gateway-caddy.service >/dev/null 2>&1 || true; fi
      ztg_log_error 'Caddy activation failed; prior project configuration/state was restored.'; exit 1
    fi
    ztg_log_info "Domain enabled: https://$domain"
    ;;
  status-domain|test-domain)
    load_state "$state_path"; ztg_log_info "Domain $name: https://$domain -> http://${target_ip}:${target_port}; staging=$staging; source=${source_cidr:-any}"
    ztg_caddy_unit_owned "$unit_path" || { ztg_log_error 'Project Caddy unit is missing or changed.'; exit 1; }
    systemctl is-active zerotier-gateway-caddy.service
    if [ "$action" = test-domain ]; then
      timeout 5 bash -c "</dev/tcp/$target_ip/$target_port" || { ztg_log_error 'Target TCP check failed.'; exit 1; }
      http_code="$(curl --silent --show-error --output /dev/null --write-out '%{http_code}' "http://$domain")" || { ztg_log_error 'HTTP listener layer failed.'; exit 1; }
      curl_tls=(); [ "$staging" = true ] && curl_tls+=(--insecure)
      https_code="$(curl "${curl_tls[@]}" --silent --show-error --output /dev/null --write-out '%{http_code}' "https://$domain")" || { ztg_log_error 'HTTPS/TLS layer failed.'; exit 1; }
      [[ "$http_code" =~ ^(2|3|401|403) ]] || { ztg_log_error "Unexpected HTTP status: $http_code"; exit 1; }
      [[ "$https_code" =~ ^(2|3|401|403) ]] || { ztg_log_error "Unexpected HTTPS status: $https_code"; exit 1; }
      ztg_log_info 'Target, HTTP, HTTPS, and certificate validation passed. Test a real page/WebSocket path if the application uses WebSocket.'
    fi
    ;;
  remove-domain)
    load_state "$state_path"; ztg_log_info "Plan: remove only domain $domain; other domain states remain."
    if [ "$apply" != true ]; then ztg_log_warn 'Preview only. Re-run with --apply.'; exit 0; fi
    ztg_require_root; binary="$(ztg_caddy_binary_path)"; [ -x "$binary" ] || { ztg_log_error 'Project Caddy binary is missing.'; exit 1; }
    ztg_caddy_unit_owned "$unit_path" || { ztg_log_error 'Project Caddy unit ownership check failed.'; exit 1; }
    ztg_assert_caddy_config_owned "$config_root"
    remaining=$(( $(ztg_count_domain_states) - 1 ))
    if [ "$remaining" -eq 0 ]; then
      old_site="$(<"$config_root/sites/$name.caddy")"; old_state="$(<"$state_path")"; old_unit="$(<"$unit_path")"
      firewall_state_existed=false; old_firewall_state=''
      if [ -f "$firewall_state_path" ]; then
        ztg_caddy_firewall_state_owned "$firewall_state_path" || { ztg_log_error 'Caddy firewall state ownership mismatch.'; exit 1; }
        firewall_state_existed=true; old_firewall_state="$(<"$firewall_state_path")"
        ztg_assert_owned_ufw_rule "$(ztg_publish_marker caddy-http)" || exit 1
        ztg_assert_owned_ufw_rule "$(ztg_publish_marker caddy-https)" || exit 1
      fi
      had_http_rule=false; had_https_rule=false
      if ztg_ufw_active; then
        ztg_ufw_rule_numbers "$(ztg_publish_marker caddy-http)" | grep -q . && had_http_rule=true
        ztg_ufw_rule_numbers "$(ztg_publish_marker caddy-https)" | grep -q . && had_https_rule=true
      fi
      systemctl disable --now zerotier-gateway-caddy.service || { ztg_log_error 'Project Caddy could not be stopped; nothing was removed.'; exit 1; }
      firewall_remove_failed=false
      ztg_remove_owned_ufw_rule "$(ztg_publish_marker caddy-http)" || firewall_remove_failed=true
      ztg_remove_owned_ufw_rule "$(ztg_publish_marker caddy-https)" || firewall_remove_failed=true
      if $firewall_remove_failed; then
        ztg_remove_owned_ufw_rule "$(ztg_publish_marker caddy-http)" || true
        ztg_remove_owned_ufw_rule "$(ztg_publish_marker caddy-https)" || true
        if $had_http_rule; then ztg_add_owned_ufw_rule caddy-http 0.0.0.0 80 '' || ztg_log_error 'The prior HTTP UFW rule could not be fully restored.'; fi
        if $had_https_rule; then ztg_add_owned_ufw_rule caddy-https 0.0.0.0 443 '' || ztg_log_error 'The prior HTTPS UFW rule could not be fully restored.'; fi
        systemctl enable --now zerotier-gateway-caddy.service >/dev/null 2>&1 || true
        ztg_log_error 'Project UFW cleanup failed; Caddy was restarted and files/state were kept.'; exit 1
      fi
      rm -f "$config_root/sites/$name.caddy" "$state_path" "$unit_path" "$firewall_state_path"
      if ! systemctl daemon-reload; then
        printf '%s\n' "$old_site" > "$config_root/sites/$name.caddy"; chmod 0640 "$config_root/sites/$name.caddy"; chown "root:$ZTG_CADDY_USER" "$config_root/sites/$name.caddy"
        ztg_atomic_write "$state_path" "$old_state" 0600; printf '%s\n' "$old_unit" > "$unit_path"; chmod 0644 "$unit_path"
        if $firewall_state_existed; then ztg_atomic_write "$firewall_state_path" "$old_firewall_state" 0600; fi
        $had_http_rule && ztg_add_owned_ufw_rule caddy-http 0.0.0.0 80 '' || true
        $had_https_rule && ztg_add_owned_ufw_rule caddy-https 0.0.0.0 443 '' || true
        systemctl daemon-reload >/dev/null 2>&1 || true; systemctl enable --now zerotier-gateway-caddy.service >/dev/null 2>&1 || true
        ztg_log_error 'systemd reload failed; project files, state, firewall, and service were restored.'; exit 1
      fi
      ztg_log_info 'Last domain removed; project Caddy stopped. Project binary and certificate data were retained for recovery.'
    else
      candidate="$(mktemp -d)"; trap 'rm -rf "$candidate"' EXIT; render_candidate "$candidate" '' '' "$name"
      "$binary" validate --config "$candidate/Caddyfile" --adapter caddyfile >/dev/null
      old_site="$(<"$config_root/sites/$name.caddy")"; old_state="$(<"$state_path")"
      rm -f "$config_root/sites/$name.caddy"; rm -f "$state_path"
      if ! systemctl reload zerotier-gateway-caddy.service; then
        printf '%s\n' "$old_site" > "$config_root/sites/$name.caddy"; chmod 0640 "$config_root/sites/$name.caddy"; chown "root:$ZTG_CADDY_USER" "$config_root/sites/$name.caddy"
        ztg_atomic_write "$state_path" "$old_state" 0600; systemctl reload zerotier-gateway-caddy.service >/dev/null 2>&1 || true
        ztg_log_error 'Reload failed after removal; the domain file and state were restored.'; exit 1
      fi
      ztg_log_info "Domain removed: $name"
    fi
    ;;
esac
