#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$ROOT/scripts/ubuntu/lib/logging.sh"
source "$ROOT/scripts/ubuntu/lib/state.sh"
source "$ROOT/scripts/ubuntu/lib/upgrade.sh"

fail() { printf 'FAIL: %s\n' "$1" >&2; exit 1; }
assert_eq() { [ "$1" = "$2" ] || fail "expected '$2', got '$1'"; }

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

mkdir -p "$tmp/source/.git" "$tmp/historical/etc/systemd/system" "$tmp/modular/etc/systemd/system" "$tmp/mixed/etc/systemd/system"
printf '1.4.0-dev\n' > "$tmp/source/VERSION"
touch "$tmp/historical/etc/systemd/system/zerotier-gateway.service"
touch "$tmp/modular/etc/systemd/system/sing-box-zt-proxy.service"
touch "$tmp/mixed/etc/systemd/system/zerotier-gateway.service" "$tmp/mixed/etc/systemd/system/sing-box-zt-proxy.service"

assert_eq "$(ztg_detect_installation "$tmp/historical" "$tmp/source")" "historical-gateway"
assert_eq "$(ztg_detect_installation "$tmp/modular" "$tmp/source")" "modular-proxy"
assert_eq "$(ztg_detect_installation "$tmp/mixed" "$tmp/source")" "unknown-mixed"
assert_eq "$(ztg_detect_installation "$tmp/empty" "$tmp/source")" "source-only"

export ZTG_STATE_ROOT="$tmp/state"
state_file="$ZTG_STATE_ROOT/installation.json"
ztg_write_installation_state "$state_file" "1.4.0-dev" "source-only" "abc123" "2026-07-15T00:00:00Z"
assert_eq "$(ztg_read_json_scalar "$state_file" lastAppliedVersion)" "1.4.0-dev"
assert_eq "$(ztg_read_json_scalar "$state_file" installationFingerprint)" "source-only"
ztg_validate_state_identity "$state_file" installation host || fail 'Valid installation state was rejected.'

future_state="$tmp/future.json"
sed 's/"schemaVersion": 1/"schemaVersion": 2/' "$state_file" > "$future_state"
! ztg_validate_state_identity "$future_state" installation host >/dev/null 2>&1 || fail 'Future Ubuntu state schema was accepted.'

presence_backup="$tmp/presence-backup"
mkdir -p "$presence_backup/state"
printf '{"sibling":true}\n' > "$presence_backup/state/proxy-pool.json"
ztg_restore_management_state "$presence_backup"
[ ! -e "$state_file" ] || fail 'Rollback did not restore installation state absence.'
[ -f "$ZTG_STATE_ROOT/proxy-pool.json" ] || fail 'Sibling management state was not restored.'

printf '{"restored":true}\n' > "$presence_backup/state/installation.json"
ztg_restore_management_state "$presence_backup"
grep -Fq '"restored":true' "$state_file" || fail 'Rollback did not restore backed-up installation state.'

export ZTG_BACKUP_ROOT="$tmp/backups"
mkdir -p "$ZTG_BACKUP_ROOT/valid-id" "$tmp/foreign"
assert_eq "$(ztg_resolve_backup_directory valid-id)" "$ZTG_BACKUP_ROOT/valid-id"
! ztg_resolve_backup_directory '../foreign' >/dev/null 2>&1 || fail 'Rollback traversal id was accepted.'
if ln -s "$tmp/foreign" "$ZTG_BACKUP_ROOT/linked" 2>/dev/null; then
  ! ztg_resolve_backup_directory linked >/dev/null 2>&1 || fail 'Rollback symlink escaping backup root was accepted.'
fi

before="$(find "$tmp" -type f -printf '%P %s\n' | sort)"
ZTG_SYSTEM_ROOT="$tmp/empty" ZTG_STATE_ROOT="$tmp/dry-state" ZTG_BACKUP_ROOT="$tmp/dry-backup" \
  bash "$ROOT/scripts/ubuntu/upgrade.sh" --dry-run >/dev/null
after="$(find "$tmp" -type f -printf '%P %s\n' | sort)"
assert_eq "$after" "$before"

if grep -En 'systemctl[[:space:]]+(restart|reload|enable|disable)|ufw[[:space:]]+(allow|delete|insert|reset|enable|disable)|iptables[[:space:]]+(-A|-D|-F|-I|-X|-P|--flush)|tc[[:space:]]+(qdisc|filter|class)[[:space:]]+(add|del|replace|change)|install-proxy\.sh|install-relay\.sh' \
  "$ROOT/scripts/ubuntu/upgrade.sh" "$ROOT/scripts/ubuntu/lib/upgrade.sh" | grep -Ev 'Forbidden|denylist'; then
  fail 'default upgrade source contains forbidden runtime mutation command'
fi

printf 'upgrade shell tests passed\n'
