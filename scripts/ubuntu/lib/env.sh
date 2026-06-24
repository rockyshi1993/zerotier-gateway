#!/usr/bin/env bash

ZTG_ENV_FILE=""
ZTG_DRY_RUN=false

ztg_parse_common_args() {
  ZTG_ENV_FILE="$ZTG_ROOT/.env"
  ZTG_DRY_RUN=false
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --env)
        if [ "$#" -lt 2 ]; then
          ztg_log_error "--env requires a path."
          exit 2
        fi
        ZTG_ENV_FILE="$2"
        shift 2
        ;;
      --dry-run)
        ZTG_DRY_RUN=true
        shift
        ;;
      -h|--help)
        ztg_show_common_help
        exit 0
        ;;
      *)
        ztg_log_error "Unknown argument: $1"
        ztg_show_common_help
        exit 2
        ;;
    esac
  done
}

ztg_load_env() {
  if [ ! -f "$ZTG_ENV_FILE" ]; then
    ztg_log_error "Config file not found: $ZTG_ENV_FILE"
    ztg_log_error "Run: bash scripts/ubuntu/init-config.sh"
    exit 1
  fi

  ztg_load_env_file

  ZEROTIER_SUBNET="${ZEROTIER_SUBNET:-10.246.77.0/24}"
  UBUNTU_ZT_IP="${UBUNTU_ZT_IP:-10.246.77.1}"
  HOME_PC_ZT_IP="${HOME_PC_ZT_IP:-10.246.77.10}"
  WORK_PC_ZT_IP="${WORK_PC_ZT_IP:-10.246.77.20}"
  PROXY_BIND_IP="${PROXY_BIND_IP:-$UBUNTU_ZT_IP}"
  PROXY_PORT="${PROXY_PORT:-10808}"
  ENABLE_RELAY="${ENABLE_RELAY:-false}"
  RELAY_PORT="${RELAY_PORT:-443}"
  REMOTE_PORTS="${REMOTE_PORTS:-3389}"
}

ztg_trim() {
  local value="$1"
  value="${value#"${value%%[![:space:]]*}"}"
  value="${value%"${value##*[![:space:]]}"}"
  printf '%s' "$value"
}

ztg_strip_optional_quotes() {
  local value="$1"
  if [[ "$value" == \"*\" && "$value" == *\" && ${#value} -ge 2 ]]; then
    printf '%s' "${value:1:${#value}-2}"
  elif [[ "$value" == \'*\' && "$value" == *\' && ${#value} -ge 2 ]]; then
    printf '%s' "${value:1:${#value}-2}"
  else
    printf '%s' "$value"
  fi
}

ztg_load_env_file() {
  local line name value
  while IFS= read -r line || [ -n "$line" ]; do
    line="${line%$'\r'}"
    line="$(ztg_trim "$line")"
    case "$line" in
      ''|'#'*) continue ;;
    esac
    if [[ "$line" != *"="* ]]; then
      ztg_log_warn "Skip invalid config line: $line"
      continue
    fi
    name="$(ztg_trim "${line%%=*}")"
    value="$(ztg_trim "${line#*=}")"
    if ! [[ "$name" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]]; then
      ztg_log_warn "Skip invalid config key: $name"
      continue
    fi
    value="$(ztg_strip_optional_quotes "$value")"
    printf -v "$name" '%s' "$value"
    export "$name"
  done < "$ZTG_ENV_FILE"
}
