#!/usr/bin/env bash

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
tmp_bin="$(mktemp -d)"
trap '/bin/rm -rf "$tmp_bin"' EXIT

printf '#!/bin/sh\nexit 0\n' > "$tmp_bin/apt-get"
printf '#!/bin/sh\nexit 1\n' > "$tmp_bin/apt-cache"
chmod +x "$tmp_bin/apt-get" "$tmp_bin/apt-cache"

PATH="$tmp_bin"
source "$ROOT/scripts/ubuntu/lib/sing-box.sh"

ztg_log_info() { printf '[INFO] %s\n' "$*"; }
ztg_log_step() { printf '==> %s\n' "$*"; }
ztg_run() { printf '[RUN] %s\n' "$*"; }
ztg_write_sagernet_sources() { printf '[WRITE] sagernet.sources\n'; }

ZTG_DRY_RUN=false
output="$(ztg_install_sing_box)"

case "$output" in
  *"sing-box is not available in current apt sources"*) ;;
  *) echo "installer did not explain missing sing-box apt package" >&2; exit 1 ;;
esac

case "$output" in
  *"[RUN] apt-get install -y curl ca-certificates"*) ;;
  *) echo "installer did not install apt repository prerequisites" >&2; exit 1 ;;
esac

case "$output" in
  *"[RUN] curl -fsSL https://sing-box.app/gpg.key -o /etc/apt/keyrings/sagernet.asc"*) ;;
  *) echo "installer did not fetch official SagerNet apt key" >&2; exit 1 ;;
esac

case "$output" in
  *"[WRITE] sagernet.sources"*) ;;
  *) echo "installer did not write SagerNet apt source" >&2; exit 1 ;;
esac

case "$output" in
  *"[RUN] apt-get install -y sing-box"*) ;;
  *) echo "installer did not retry sing-box installation" >&2; exit 1 ;;
esac

echo "sing-box-install.test.sh passed"
