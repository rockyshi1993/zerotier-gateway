#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"; ZTG_ROOT="$ROOT"
source "$ROOT/scripts/ubuntu/lib/logging.sh"
source "$ROOT/scripts/ubuntu/lib/state.sh"
source "$ROOT/scripts/ubuntu/lib/rate-limit.sh"
source "$ROOT/scripts/ubuntu/lib/publish.sh"
source "$ROOT/scripts/ubuntu/lib/caddy.sh"

fail() { printf 'FAIL: %s\n' "$1" >&2; exit 1; }
contains() { printf '%s' "$1" | grep -Fq "$2" || fail "$3"; }

ztg_validate_domain_name 'site.example.com' || fail 'Valid domain rejected.'
! ztg_validate_domain_name 'https://site.example.com' || fail 'URL accepted as domain.'
! ztg_validate_domain_name 'Site.Example.com' || fail 'Non-normalized domain accepted.'
site="$(ztg_render_caddy_site demo site.example.com 10.246.77.30 3000 false '' '')"
contains "$site" 'site.example.com {' 'Domain block missing.'
contains "$site" 'route {' 'Order-preserving route block missing.'
contains "$site" 'reverse_proxy 10.246.77.30:3000' 'Reverse proxy missing.'
! printf '%s' "$site" | grep -Fq 'tls {' || fail 'Production site should use automatic HTTPS defaults.'
staging_site="$(ztg_render_caddy_site staging staging.example.com 10.246.77.31 8080 true user '$2a$14$hash')"
contains "$staging_site" 'basic_auth {' 'Basic auth missing.'
contains "$staging_site" 'acme-staging' 'Staging CA missing.'
restricted_site="$(ztg_render_caddy_site limited limited.example.com 10.246.77.31 8080 false '' '' '198.51.100.0/24')"
contains "$restricted_site" 'not remote_ip 198.51.100.0/24' 'Source restriction missing.'
service="$(ztg_render_caddy_service /opt/ztg/caddy /etc/ztg/caddy /var/lib/ztg/caddy)"
contains "$service" '# Managed-By: zerotier-gateway-caddy' 'Unit ownership marker missing.'
contains "$service" 'ProtectSystem=strict' 'Systemd hardening missing.'

temp="$(mktemp -d)"; trap 'rm -rf "$temp"' EXIT
owned="$temp/owned"; foreign="$temp/foreign"
mkdir -p "$owned/sites" "$foreign"
ztg_render_caddy_main > "$owned/Caddyfile"; printf '# Managed-By: zerotier-gateway-domain-demo\ndemo.example.com { respond "ok" }\n' > "$owned/sites/demo.caddy"
ztg_assert_caddy_config_owned "$owned" || fail 'Owned config was rejected.'
printf 'foreign\n' > "$foreign/Caddyfile"
! ztg_assert_caddy_config_owned "$foreign" >/dev/null 2>&1 || fail 'Foreign config was accepted.'

output="$(ZTG_STATE_ROOT="$temp/state" ZTG_CADDY_CONFIG_ROOT="$temp/config" ZTG_CADDY_DATA_ROOT="$temp/data" ZTG_SYSTEMD_DIR="$temp/units" bash "$ROOT/scripts/ubuntu/manage-publish.sh" add-domain --name demo --domain site.example.com --target-ip 10.246.77.30 --target-port 3000 2>&1)"
[ ! -e "$temp/state" ] || fail 'Preview created state.'
[ ! -e "$temp/config" ] || fail 'Preview created config.'
[ ! -e "$temp/units" ] || fail 'Preview created unit.'
contains "$output" 'Preview only' 'Preview message missing.'

export ZTG_STATE_ROOT="$temp/state-write"
path="$(ztg_domain_state_path demo)"; ztg_write_domain_state "$path" demo site.example.com 10.246.77.30 3000 false '' '' '' 1
[ "$(ztg_read_json_scalar "$path" objectType)" = publish-domain ] || fail 'Domain state type mismatch.'
[ "$(ztg_json_boolean "$path" acmeStaging)" = false ] || fail 'Staging state mismatch.'
ztg_domain_in_use site.example.com || fail 'Managed domain lookup failed.'
! ztg_domain_in_use site.example.com demo || fail 'Managed domain exclusion failed.'
firewall_path="$(ztg_caddy_firewall_state_path)"; ztg_write_caddy_firewall_state "$firewall_path" 1
ztg_caddy_firewall_state_owned "$firewall_path" || fail 'Owned Caddy firewall state was rejected.'
[ "$(ztg_read_json_scalar "$firewall_path" objectType)" = publish-firewall ] || fail 'Caddy firewall state type mismatch.'

future_firewall="$temp/future-firewall.json"
sed 's/"schemaVersion": 1/"schemaVersion": 2/' "$firewall_path" > "$future_firewall"
! ztg_caddy_firewall_state_owned "$future_firewall" >/dev/null 2>&1 || fail 'Caddy accepted a future firewall state schema.'

future_domain="$temp/future-domain.json"
sed 's/"schemaVersion": 1/"schemaVersion": 2/' "$path" > "$future_domain"
mv "$future_domain" "$path"
set +e
future_output="$(ZTG_STATE_ROOT="$ZTG_STATE_ROOT" bash "$ROOT/scripts/ubuntu/manage-publish.sh" status-domain --name demo 2>&1)"
future_rc=$?
set -e
[ "$future_rc" -ne 0 ] || fail 'Domain manager accepted a future state schema.'
contains "$future_output" 'Unsupported or missing state schema' 'Domain manager schema rejection was not diagnostic.'

set +e
future_add_output="$(ZTG_STATE_ROOT="$ZTG_STATE_ROOT" bash "$ROOT/scripts/ubuntu/manage-publish.sh" add-domain --name another --domain another.example.com --target-ip 10.246.77.31 --target-port 3001 2>&1)"
future_add_rc=$?
set -e
[ "$future_add_rc" -ne 0 ] || fail 'Domain conflict lookup treated a future state schema as available.'
contains "$future_add_output" 'Unsupported or missing state schema' 'Domain conflict lookup schema rejection was not diagnostic.'

printf 'Caddy tests passed.\n'
