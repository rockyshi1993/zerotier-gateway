#!/usr/bin/env bash

ZTG_STATE_SCHEMA_VERSION=1
ZTG_STATE_OWNER="zerotier-gateway"

ztg_state_root() {
  printf '%s' "${ZTG_STATE_ROOT:-/var/lib/zerotier-gateway/state}"
}

ztg_backup_root() {
  printf '%s' "${ZTG_BACKUP_ROOT:-/var/lib/zerotier-gateway/backups}"
}

ztg_resolve_backup_directory() {
  local backup_id="${1:-}"
  local root resolved_root candidate resolved_candidate
  [[ "$backup_id" =~ ^[A-Za-z0-9][A-Za-z0-9._-]{0,127}$ ]] || {
    ztg_log_error "Invalid backup id: $backup_id"
    return 1
  }
  command -v realpath >/dev/null 2>&1 || {
    ztg_log_error "realpath is required to validate a rollback backup."
    return 1
  }
  root="$(ztg_backup_root)"
  [ -d "$root" ] || {
    ztg_log_error "Backup root not found: $root"
    return 1
  }
  resolved_root="$(realpath -e -- "$root")" || return 1
  candidate="$resolved_root/$backup_id"
  [ -d "$candidate" ] || {
    ztg_log_error "Backup not found: $candidate"
    return 1
  }
  resolved_candidate="$(realpath -e -- "$candidate")" || return 1
  [ "$(dirname "$resolved_candidate")" = "$resolved_root" ] || {
    ztg_log_error "Backup must be a direct child of the project backup root: $candidate"
    return 1
  }
  printf '%s' "$resolved_candidate"
}

ztg_management_lock_path() {
  printf '%s/management.lock' "$(dirname "$(ztg_state_root)")"
}

ztg_acquire_management_lock() {
  local timeout="${ZTG_MANAGEMENT_LOCK_TIMEOUT_SECONDS:-60}"
  local lock_path
  [ -z "${ZTG_MANAGEMENT_LOCK_FD:-}" ] || return 0
  command -v flock >/dev/null 2>&1 || {
    ztg_log_error "flock is required for management mutations."
    return 1
  }
  [[ "$timeout" =~ ^[0-9]+$ ]] && [ "$timeout" -ge 1 ] || {
    ztg_log_error "Invalid management lock timeout: $timeout"
    return 1
  }
  lock_path="$(ztg_management_lock_path)"
  install -d -m 0750 "$(dirname "$lock_path")"
  exec {ZTG_MANAGEMENT_LOCK_FD}>"$lock_path"
  if ! flock -w "$timeout" "$ZTG_MANAGEMENT_LOCK_FD"; then
    ztg_log_error "Timed out waiting for the management operation lock: $lock_path"
    ztg_release_management_lock
    return 1
  fi
}

ztg_release_management_lock() {
  local descriptor="${ZTG_MANAGEMENT_LOCK_FD:-}"
  [ -n "$descriptor" ] || return 0
  flock -u "$descriptor" >/dev/null 2>&1 || true
  eval "exec ${descriptor}>&-"
  unset ZTG_MANAGEMENT_LOCK_FD
}

ztg_project_version() {
  local version_file="${1:-$ZTG_ROOT/VERSION}"
  if [ ! -f "$version_file" ]; then
    ztg_log_error "Project VERSION file not found: $version_file"
    return 1
  fi
  tr -d '\r\n' < "$version_file"
}

ztg_validate_object_name() {
  local value="${1:-}"
  [[ "$value" =~ ^[A-Za-z0-9][A-Za-z0-9._-]{0,63}$ ]]
}

ztg_json_escape() {
  local value="${1:-}"
  value="${value//\\/\\\\}"
  value="${value//\"/\\\"}"
  value="${value//$'\n'/\\n}"
  value="${value//$'\r'/\\r}"
  value="${value//$'\t'/\\t}"
  printf '%s' "$value"
}

ztg_sha256_file() {
  local path="$1"
  if [ ! -f "$path" ]; then
    printf '%s' "missing"
    return 0
  fi
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$path" | awk '{print $1}'
  elif command -v shasum >/dev/null 2>&1; then
    shasum -a 256 "$path" | awk '{print $1}'
  else
    ztg_log_error "sha256sum or shasum is required."
    return 1
  fi
}

ztg_atomic_write() {
  local target="$1"
  local content="$2"
  local mode="${3:-0600}"
  local directory temporary
  directory="$(dirname "$target")"
  install -d -m 0750 "$directory"
  temporary="$(mktemp "$directory/.ztg-state.XXXXXX")"
  printf '%s\n' "$content" > "$temporary"
  chmod "$mode" "$temporary"
  mv -f "$temporary" "$target"
}

ztg_write_installation_state() {
  local target="$1"
  local version="$2"
  local fingerprint="$3"
  local head="$4"
  local timestamp="$5"
  local json
  json=$(cat <<JSON
{
  "schemaVersion": ${ZTG_STATE_SCHEMA_VERSION},
  "objectVersion": 1,
  "owner": "${ZTG_STATE_OWNER}",
  "objectType": "installation",
  "objectName": "host",
  "enabled": false,
  "lastAppliedVersion": "$(ztg_json_escape "$version")",
  "generation": 1,
  "installationFingerprint": "$(ztg_json_escape "$fingerprint")",
  "sourceHead": "$(ztg_json_escape "$head")",
  "updatedAt": "$(ztg_json_escape "$timestamp")"
}
JSON
)
  ztg_atomic_write "$target" "$json" 0600
}

ztg_read_json_scalar() {
  local path="$1"
  local key="$2"
  [ -f "$path" ] || return 1
  sed -nE 's/^[[:space:]]*"'"$key"'"[[:space:]]*:[[:space:]]*"([^"]*)".*/\1/p' "$path" | head -n 1
}

ztg_read_json_number() {
  local path="$1"
  local key="$2"
  [ -f "$path" ] || return 1
  sed -nE 's/^[[:space:]]*"'"$key"'"[[:space:]]*:[[:space:]]*([0-9]+).*/\1/p' "$path" | head -n 1
}

ztg_validate_state_identity() {
  local path="$1"
  local expected_type="$2"
  local expected_name="$3"
  local schema owner object_type object_name
  [ -f "$path" ] || {
    ztg_log_error "Managed state not found: $path"
    return 1
  }
  schema="$(ztg_read_json_number "$path" schemaVersion 2>/dev/null || true)"
  owner="$(ztg_read_json_scalar "$path" owner 2>/dev/null || true)"
  object_type="$(ztg_read_json_scalar "$path" objectType 2>/dev/null || true)"
  object_name="$(ztg_read_json_scalar "$path" objectName 2>/dev/null || true)"
  [ "$schema" = "$ZTG_STATE_SCHEMA_VERSION" ] || {
    ztg_log_error "Unsupported or missing state schema in $path: ${schema:-missing}"
    return 1
  }
  [ "$owner" = "$ZTG_STATE_OWNER" ] || {
    ztg_log_error "State ownership mismatch: $path"
    return 1
  }
  [ "$object_type" = "$expected_type" ] && [ "$object_name" = "$expected_name" ] || {
    ztg_log_error "State type/name mismatch: $path"
    return 1
  }
}
