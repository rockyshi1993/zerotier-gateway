#!/usr/bin/env bash

ztg_render_template() {
  local input="$1"
  local output="$2"
  mkdir -p "$(dirname "$output")"
  cp "$input" "$output"
  local placeholder name value
  while IFS= read -r placeholder; do
    [ -n "$placeholder" ] || continue
    name="${placeholder#\$\{}"
    name="${name%\}}"
    value="${!name:-}"
    value="${value//\\/\\\\}"
    value="${value//&/\\&}"
    value="${value//|/\\|}"
    sed -i "s|\${$name}|$value|g" "$output"
  done < <(grep -oE '\$\{[A-Za-z_][A-Za-z0-9_]*\}' "$input" | sort -u || true)
}
