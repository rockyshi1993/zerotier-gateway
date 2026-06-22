#!/usr/bin/env bash

set -euo pipefail

ZTG_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ZTG_ROOT="$(cd "$ZTG_LIB_DIR/../../.." && pwd)"
ZTG_ARTIFACTS_DIR="$ZTG_ROOT/artifacts"

source "$ZTG_LIB_DIR/logging.sh"

ztg_show_common_help() {
  cat <<'HELP'
Common options:
  --env <path>     Override config path. Default: .env in project root.
  --dry-run        Print actions without making system changes.
  -h, --help       Show help.
HELP
}

ztg_require_root() {
  if [ "${ZTG_DRY_RUN:-false}" = "true" ]; then
    return 0
  fi
  if [ "$(id -u)" -ne 0 ]; then
    ztg_log_error "Run this command with sudo, or use --dry-run for preview."
    exit 1
  fi
}

ztg_run() {
  if [ "${ZTG_DRY_RUN:-false}" = "true" ]; then
    printf '[DRY-RUN] %s\n' "$*"
    return 0
  fi
  "$@"
}

ztg_ensure_artifacts() {
  mkdir -p "$ZTG_ARTIFACTS_DIR"
}
