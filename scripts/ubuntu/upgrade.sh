#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/common.sh"
source "$SCRIPT_DIR/lib/state.sh"
source "$SCRIPT_DIR/lib/upgrade.sh"

ZTG_DRY_RUN=false
ZTG_APPLY=true
ZTG_ROLLBACK_ID=""
ZTG_SYSTEM_ROOT="${ZTG_SYSTEM_ROOT:-/}"

show_help() {
  cat <<'HELP'
Usage:
  sudo bash scripts/ubuntu/upgrade.sh --dry-run
  sudo bash scripts/ubuntu/upgrade.sh
  sudo bash scripts/ubuntu/upgrade.sh --rollback <backup-id>

The default apply path updates only project management state. It does not restart
or reconfigure ZeroTier, proxy, gateway, relay, firewall, tc, PAC, or new features.
HELP
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --dry-run) ZTG_DRY_RUN=true; ZTG_APPLY=false; shift ;;
    --apply) ZTG_APPLY=true; shift ;;
    --rollback)
      [ "$#" -ge 2 ] || { ztg_log_error "--rollback requires a backup id."; exit 2; }
      ZTG_ROLLBACK_ID="$2"; shift 2 ;;
    -h|--help) show_help; exit 0 ;;
    *) ztg_log_error "Unknown argument: $1"; show_help; exit 2 ;;
  esac
done

version="$(ztg_project_version)"
head="$(ztg_git_head)"
fingerprint="$(ztg_detect_installation "$ZTG_SYSTEM_ROOT" "$ZTG_ROOT")"
state_file="$(ztg_state_root)/installation.json"
installed_version="$(ztg_read_json_scalar "$state_file" lastAppliedVersion 2>/dev/null || true)"

ztg_log_step "ZeroTier Gateway management upgrade"
ztg_log_info "Source HEAD: $head"
ztg_log_info "Target version: $version"
ztg_log_info "Installed management version: ${installed_version:-not-recorded}"
ztg_log_info "Installation fingerprint: $fingerprint"
ztg_log_info "State: $state_file"
ztg_log_info "New capabilities after upgrade: disabled"

case "$fingerprint" in
  historical-gateway|modular-proxy|source-only) ;;
  *)
    ztg_log_error "Installation ownership is unknown or mixed: $fingerprint"
    ztg_log_error "No files or services were changed. Inspect historical and modular anchors before retrying."
    exit 1
    ;;
esac

if [ -n "$ZTG_ROLLBACK_ID" ]; then
  ztg_require_root
  backup_dir="$(ztg_resolve_backup_directory "$ZTG_ROLLBACK_ID")" || exit 1
  ztg_log_warn "Rollback restores project management state only; existing runtime was never changed."
  ztg_restore_management_state "$backup_dir"
  ztg_log_info "Management state restored from $backup_dir"
  exit 0
fi

backup_id="$(date -u +%Y%m%dT%H%M%SZ)-${head}"
backup_dir="$(ztg_backup_root)/$backup_id"
[ ! -e "$backup_dir" ] || { ztg_log_error "Backup destination already exists: $backup_dir"; exit 1; }

ztg_log_info "Backup destination: $backup_dir"
ztg_log_info "Plan: snapshot runtime -> back up existing project files -> verify runtime is unchanged -> record management version"
ztg_log_info "Forbidden in this path: install/uninstall, service restart/reload/enable/disable, firewall/tc/PAC/task/v2rayN changes"

if [ "$ZTG_DRY_RUN" = "true" ]; then
  ztg_log_info "[DRY-RUN] Runtime snapshot would be captured read-only."
  while IFS= read -r path; do
    source_path="$(ztg_system_path "$ZTG_SYSTEM_ROOT" "$path")"
    [ -e "$source_path" ] && ztg_log_info "[DRY-RUN] Back up $source_path"
  done < <(ztg_upgrade_backup_paths)
  [ -f "$ZTG_ROOT/.env" ] && ztg_log_info "[DRY-RUN] Back up $ZTG_ROOT/.env"
  ztg_log_info "[DRY-RUN] No directory, state, service, listener, task, firewall, PAC, or proxy configuration was changed."
  exit 0
fi

ztg_require_root
before_snapshot="$(ztg_capture_runtime_snapshot "$ZTG_SYSTEM_ROOT")"
ztg_create_upgrade_backup "$backup_dir" "$ZTG_SYSTEM_ROOT" "$ZTG_ROOT"
after_snapshot="$(ztg_capture_runtime_snapshot "$ZTG_SYSTEM_ROOT")"

if [ "$before_snapshot" != "$after_snapshot" ]; then
  ztg_log_error "Runtime invariant changed during the management upgrade. State was not committed."
  ztg_log_error "Backup: $backup_dir"
  exit 1
fi

timestamp="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
ztg_write_installation_state "$state_file" "$version" "$fingerprint" "$head" "$timestamp"
ztg_log_info "Management upgrade completed without restarting or reconfiguring existing runtime."
ztg_log_info "Installed management version: $version"
ztg_log_info "Rollback command: sudo bash scripts/ubuntu/upgrade.sh --rollback $backup_id"
ztg_log_info "Next verification: sudo bash scripts/ubuntu/health-check.sh"
