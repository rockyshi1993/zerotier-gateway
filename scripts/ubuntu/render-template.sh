#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/common.sh"
source "$SCRIPT_DIR/lib/env.sh"
source "$SCRIPT_DIR/lib/template.sh"

usage() {
  cat <<'HELP'
Usage: sudo bash scripts/ubuntu/render-template.sh <template> <output> [--env <path>]
HELP
  ztg_show_common_help
}

if [ "$#" -lt 2 ]; then
  usage
  exit 2
fi

TEMPLATE="$1"
OUTPUT="$2"
shift 2
ztg_parse_common_args "$@"
ztg_load_env
ztg_render_template "$TEMPLATE" "$OUTPUT"
ztg_log_info "Rendered template to $OUTPUT"
