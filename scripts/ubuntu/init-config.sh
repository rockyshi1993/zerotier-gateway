#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ZTG_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
ENV_FILE="$ZTG_ROOT/.env"

show_help() {
  cat <<'HELP'
Usage:
  bash scripts/ubuntu/init-config.sh

Options:
  --env <path>   Write config to another path. Default: .env in project root.
  -h, --help     Show help.
HELP
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --env)
      if [ "$#" -lt 2 ]; then
        echo "[ERROR] --env requires a path." >&2
        exit 2
      fi
      ENV_FILE="$2"
      shift 2
      ;;
    -h|--help)
      show_help
      exit 0
      ;;
    *)
      echo "[ERROR] Unknown argument: $1" >&2
      show_help
      exit 2
      ;;
  esac
done

if [[ "$ENV_FILE" != /* ]]; then
  ENV_FILE="$ZTG_ROOT/$ENV_FILE"
fi

declare -A CURRENT=()

trim() {
  local value="$1"
  value="${value#"${value%%[![:space:]]*}"}"
  value="${value%"${value##*[![:space:]]}"}"
  printf '%s' "$value"
}

strip_optional_quotes() {
  local value="$1"
  if [[ "$value" == \"*\" && "$value" == *\" && ${#value} -ge 2 ]]; then
    printf '%s' "${value:1:${#value}-2}"
  elif [[ "$value" == \'*\' && "$value" == *\' && ${#value} -ge 2 ]]; then
    printf '%s' "${value:1:${#value}-2}"
  else
    printf '%s' "$value"
  fi
}

load_current_env() {
  [ -f "$ENV_FILE" ] || return 0

  local line key value
  while IFS= read -r line || [ -n "$line" ]; do
    line="${line%$'\r'}"
    line="$(trim "$line")"
    case "$line" in
      ''|'#'*) continue ;;
    esac
    [[ "$line" == *"="* ]] || continue
    key="$(trim "${line%%=*}")"
    value="$(trim "${line#*=}")"
    [[ "$key" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]] || continue
    CURRENT["$key"]="$(strip_optional_quotes "$value")"
  done < "$ENV_FILE"
}

current_or_default() {
  local key="$1"
  local default="$2"
  if [ -n "${CURRENT[$key]+set}" ]; then
    printf '%s' "${CURRENT[$key]}"
  else
    printf '%s' "$default"
  fi
}

prompt_value() {
  local label="$1"
  local default="$2"
  local required="${3:-false}"
  local value=""

  while true; do
    if [ -n "$default" ]; then
      read -r -p "$label [$default]: " value || value=""
      value="${value:-$default}"
    else
      read -r -p "$label: " value || value=""
    fi

    if [ "$required" != "true" ] || [ -n "$value" ]; then
      printf '%s' "$value"
      return 0
    fi
    echo "这个值不能为空。"
  done
}

prompt_network_id() {
  local default="$1"
  local value=""
  while true; do
    value="$(prompt_value "ZeroTier 网络编号，16 位" "$default" true)"
    if [[ "$value" =~ ^[0-9a-fA-F]{16}$ ]]; then
      printf '%s' "$value"
      return 0
    fi
    echo "网络编号必须是 16 位十六进制字符，例如 0123456789abcdef。"
  done
}

prompt_yes_no() {
  local label="$1"
  local default="$2"
  local suffix="[y/N]"
  local answer=""
  if [ "$default" = "true" ]; then
    suffix="[Y/n]"
  fi

  while true; do
    read -r -p "$label $suffix: " answer || answer=""
    answer="$(printf '%s' "$answer" | tr '[:upper:]' '[:lower:]')"
    if [ -z "$answer" ]; then
      [ "$default" = "true" ] && return 0 || return 1
    fi
    case "$answer" in
      y|yes) return 0 ;;
      n|no) return 1 ;;
      *) echo "请输入 y 或 n。" ;;
    esac
  done
}

ipv4_is_public() {
  local ip="$1"
  local a b c d
  [[ "$ip" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]] || return 1
  IFS='.' read -r a b c d <<< "$ip"
  for part in "$a" "$b" "$c" "$d"; do
    [[ "$part" =~ ^[0-9]+$ ]] || return 1
    [ "$part" -ge 0 ] && [ "$part" -le 255 ] || return 1
  done
  [ "$a" -eq 10 ] && return 1
  [ "$a" -eq 127 ] && return 1
  [ "$a" -eq 169 ] && [ "$b" -eq 254 ] && return 1
  [ "$a" -eq 172 ] && [ "$b" -ge 16 ] && [ "$b" -le 31 ] && return 1
  [ "$a" -eq 192 ] && [ "$b" -eq 168 ] && return 1
  [ "$a" -eq 100 ] && [ "$b" -ge 64 ] && [ "$b" -le 127 ] && return 1
  [ "$a" -ge 224 ] && return 1
  return 0
}

detect_public_ipv4() {
  local candidate=""
  if command -v ip >/dev/null 2>&1; then
    candidate="$(ip -4 route get 1.1.1.1 2>/dev/null | awk '{for (i=1; i<=NF; i++) if ($i=="src") {print $(i+1); exit}}' || true)"
    if ipv4_is_public "$candidate"; then
      printf '%s' "$candidate"
      return 0
    fi
  fi
  if command -v hostname >/dev/null 2>&1; then
    for candidate in $(hostname -I 2>/dev/null || true); do
      if ipv4_is_public "$candidate"; then
        printf '%s' "$candidate"
        return 0
      fi
    done
  fi
  return 1
}

load_current_env

if [ -f "$ENV_FILE" ]; then
  echo "[INFO] 检测到已有配置：$ENV_FILE"
  echo "[INFO] 直接回车会沿用当前值。"
fi

network_id="$(prompt_network_id "$(current_or_default ZEROTIER_NETWORK_ID "")")"
subnet="$(prompt_value "ZeroTier 子网段" "$(current_or_default ZEROTIER_SUBNET "10.246.77.0/24")" true)"
ubuntu_ip="$(prompt_value "Ubuntu 节点 ZeroTier IP" "$(current_or_default UBUNTU_ZT_IP "10.246.77.1")" true)"
home_ip="$(prompt_value "家里 Windows ZeroTier IP" "$(current_or_default HOME_PC_ZT_IP "10.246.77.10")" true)"
work_ip="$(prompt_value "公司 Windows ZeroTier IP" "$(current_or_default WORK_PC_ZT_IP "10.246.77.20")" true)"
proxy_port="$(prompt_value "代理端口" "$(current_or_default PROXY_PORT "10808")" true)"

public_default="false"
if [ "$(current_or_default PROXY_PUBLIC_ACCESS "false")" = "true" ]; then
  public_default="true"
fi

proxy_public_access="false"
proxy_bind_ip="$ubuntu_ip"
proxy_connect_host="$ubuntu_ip"
proxy_allowed_client_cidrs=""

if prompt_yes_no "是否启用代理公网入口提速" "$public_default"; then
  public_bind_default="$(current_or_default PROXY_BIND_IP "0.0.0.0")"
  public_connect_default="$(current_or_default PROXY_CONNECT_HOST "")"
  if [ "$public_default" != "true" ] || [ -z "$public_bind_default" ] || [ "$public_bind_default" = "$ubuntu_ip" ]; then
    public_bind_default="0.0.0.0"
  fi
  if [ "$public_default" != "true" ] || [ -z "$public_connect_default" ] || [ "$public_connect_default" = "$ubuntu_ip" ]; then
    public_connect_default=""
    public_connect_default="$(detect_public_ipv4 || true)"
  fi
  proxy_public_access="true"
  proxy_bind_ip="$public_bind_default"
  echo "[INFO] 代理监听地址自动设置为：$proxy_bind_ip"
  if [ -n "$public_connect_default" ]; then
    echo "[INFO] 已自动识别客户端连接代理地址：$public_connect_default"
    proxy_connect_host="$(prompt_value "客户端连接代理地址，直接回车使用自动识别值" "$public_connect_default" false)"
  else
    proxy_connect_host="$(prompt_value "客户端连接代理地址，未能自动识别时填服务器公网 IP" "" true)"
  fi
  proxy_allowed_client_cidrs="$(prompt_value "允许访问公网代理的公网 IP/CIDR，留空表示全部来源" "$(current_or_default PROXY_ALLOWED_CLIENT_CIDRS "")" false)"
  if [ -z "$proxy_allowed_client_cidrs" ]; then
    echo "[WARN] 未填写公网访问白名单，表示允许全部来源访问代理端口。"
  fi
else
  proxy_bind_ip="$ubuntu_ip"
  proxy_connect_host="$ubuntu_ip"
  proxy_allowed_client_cidrs=""
fi

proxy_username="$(current_or_default PROXY_USERNAME "")"
proxy_password="$(current_or_default PROXY_PASSWORD "")"
auth_default="false"
if [ -n "$proxy_username" ] && [ -n "$proxy_password" ]; then
  auth_default="true"
fi

if prompt_yes_no "是否启用代理用户名和密码" "$auth_default"; then
  proxy_username="$(prompt_value "代理用户名" "$proxy_username" true)"
  proxy_password="$(prompt_value "代理密码" "$proxy_password" true)"
else
  proxy_username=""
  proxy_password=""
fi

mkdir -p "$(dirname "$ENV_FILE")"

cat > "$ENV_FILE" <<ENV
# ZeroTier Gateway 配置。
# 推荐通过 scripts/ubuntu/init-config.sh 或 scripts/windows/init-config.ps1 生成。

ZEROTIER_NETWORK_ID=$network_id
ZEROTIER_SUBNET=$subnet
UBUNTU_ZT_IP=$ubuntu_ip
HOME_PC_ZT_IP=$home_ip
WORK_PC_ZT_IP=$work_ip

PROXY_BIND_IP=$proxy_bind_ip
PROXY_PUBLIC_ACCESS=$proxy_public_access
PROXY_CONNECT_HOST=$proxy_connect_host
PROXY_ALLOWED_CLIENT_CIDRS=$proxy_allowed_client_cidrs
PROXY_PORT=$proxy_port
PROXY_USERNAME=$proxy_username
PROXY_PASSWORD=$proxy_password

PROXY_MODE=$(current_or_default PROXY_MODE "manual")
PROXY_DEFAULT=$(current_or_default PROXY_DEFAULT "proxy")
DIRECT_DOMAINS=$(current_or_default DIRECT_DOMAINS "localhost,*.local")
DIRECT_DOMAIN_SUFFIXES=$(current_or_default DIRECT_DOMAIN_SUFFIXES ".local")
DIRECT_IP_CIDRS=$(current_or_default DIRECT_IP_CIDRS "10.246.77.0/24,10.0.0.0/8,172.16.0.0/12,192.168.0.0/16")
DIRECT_PROCESS_GROUPS=$(current_or_default DIRECT_PROCESS_GROUPS "")
DIRECT_PROCESS_NAMES=$(current_or_default DIRECT_PROCESS_NAMES "")
DIRECT_PROCESS_PATHS=$(current_or_default DIRECT_PROCESS_PATHS "")
DIRECT_PROCESS_PATH_REGEX=$(current_or_default DIRECT_PROCESS_PATH_REGEX "")

ENABLE_RELAY=$(current_or_default ENABLE_RELAY "false")
RELAY_PORT=$(current_or_default RELAY_PORT "443")
RELAY_FORCE=$(current_or_default RELAY_FORCE "false")

REMOTE_PORTS=$(current_or_default REMOTE_PORTS "3389")
LOCAL_PROXY_PORT=$(current_or_default LOCAL_PROXY_PORT "20808")
ENV

echo
echo "[INFO] 已生成配置：$ENV_FILE"
echo "[INFO] 下一步 Ubuntu 安装：sudo bash scripts/ubuntu/install.sh --dry-run"
echo "[INFO] Windows 配置：.\\scripts\\windows\\setup.ps1 -Role Home 或 -Role Work"
