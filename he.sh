#!/usr/bin/env bash
# HE Tunnel Broker Manager
# Interactive Hurricane Electric IPv6 tunnel manager.

set -o pipefail

VERSION="1.1.3"
APP_NAME="HE Tunnel Broker Manager"

CONFIG_DIR="${CONFIG_DIR:-/etc/he-tunnel}"
CONFIG_FILE="${CONFIG_FILE:-${CONFIG_DIR}/config.conf}"
MANAGER_FILE="${MANAGER_FILE:-${CONFIG_DIR}/manager.conf}"

INSTALL_DIR="${INSTALL_DIR:-/opt/he-tunnel-manager}"
SERVICE_NAME="${SERVICE_NAME:-he-tunnel.service}"
TUNNEL_NAME="${TUNNEL_NAME:-he-ipv6}"
FIREWALL_CHAIN="${FIREWALL_CHAIN:-HE_TUNNEL_MANAGER}"

GITHUB_REPO="${GITHUB_REPO:-ccqwertyui/he-tunnel-manager}"
GITHUB_BRANCH="${GITHUB_BRANCH:-main}"

if [[ -f "$MANAGER_FILE" ]]; then
  # shellcheck source=/dev/null
  . "$MANAGER_FILE"
fi

RAW_BASE="${RAW_BASE:-https://raw.githubusercontent.com/${GITHUB_REPO}/${GITHUB_BRANCH}}"

if [[ -t 1 ]]; then
  RED="$(printf '\033[31m')"
  GREEN="$(printf '\033[32m')"
  YELLOW="$(printf '\033[33m')"
  BLUE="$(printf '\033[34m')"
  BOLD="$(printf '\033[1m')"
  RESET="$(printf '\033[0m')"
else
  RED=""
  GREEN=""
  YELLOW=""
  BLUE=""
  BOLD=""
  RESET=""
fi

SERVER_IPV4=""
CLIENT_IPV4=""
SERVER_IPV6=""
CLIENT_IPV6=""
ROUTED64=""
ROUTED48=""
DNS="Cloudflare"
MTU="1280"
AUTOSTART="0"
FIREWALL="0"
BLOCK_PING="1"
IPV6_PRIORITY="he"
EXIT_MODE="48"

print_ok() { printf "%b\n" "${GREEN}$*${RESET}"; }
print_warn() { printf "%b\n" "${YELLOW}$*${RESET}"; }
print_err() { printf "%b\n" "${RED}$*${RESET}" >&2; }
has_cmd() { command -v "$1" >/dev/null 2>&1; }

is_root() {
  [[ "${EUID:-$(id -u)}" -eq 0 ]]
}

require_root() {
  if ! is_root; then
    print_err "当前操作需要 root 权限，请使用 root 用户或 sudo。"
    return 1
  fi
}

pause() {
  printf "\n按 Enter 返回菜单..."
  IFS= read -r _ || true
}

clear_screen() {
  if [[ -t 1 ]] && has_cmd clear; then
    clear
  fi
}

load_config() {
  SERVER_IPV4=""
  CLIENT_IPV4=""
  SERVER_IPV6=""
  CLIENT_IPV6=""
  ROUTED64=""
  ROUTED48=""
  DNS="Cloudflare"
  MTU="1280"
  AUTOSTART="0"
  FIREWALL="0"
  BLOCK_PING="1"
  IPV6_PRIORITY="he"
  EXIT_MODE="48"

  if [[ -f "$CONFIG_FILE" ]]; then
    # shellcheck source=/dev/null
    . "$CONFIG_FILE"
  fi

  DNS="${DNS:-Cloudflare}"
  MTU="${MTU:-1280}"
  AUTOSTART="${AUTOSTART:-0}"
  FIREWALL="${FIREWALL:-0}"
  BLOCK_PING="${BLOCK_PING:-1}"
  IPV6_PRIORITY="${IPV6_PRIORITY:-he}"
  EXIT_MODE="${EXIT_MODE:-48}"
  case "$EXIT_MODE" in
    64|Routed64|routed64|ROUTED64|/64) EXIT_MODE="64" ;;
    *) EXIT_MODE="48" ;;
  esac

  case "$IPV6_PRIORITY" in
    native|Native|system|SYSTEM|原生|系统原生) IPV6_PRIORITY="native" ;;
    *) IPV6_PRIORITY="he" ;;
  esac

  case "$BLOCK_PING" in
    0|no|No|N|n|false|FALSE) BLOCK_PING="0" ;;
    *) BLOCK_PING="1" ;;
  esac
}

save_config() {
  require_root || return 1
  mkdir -p "$CONFIG_DIR" || return 1

  local tmp
  tmp="$(mktemp)" || return 1

  {
    printf '# HE Tunnel Broker Manager configuration\n'
    printf '# This file is managed by he. You may edit it manually if needed.\n'
    printf 'SERVER_IPV4=%q\n' "$SERVER_IPV4"
    printf 'CLIENT_IPV4=%q\n' "$CLIENT_IPV4"
    printf 'SERVER_IPV6=%q\n' "$SERVER_IPV6"
    printf 'CLIENT_IPV6=%q\n' "$CLIENT_IPV6"
    printf 'ROUTED64=%q\n' "$ROUTED64"
    printf 'ROUTED48=%q\n' "$ROUTED48"
    printf 'DNS=%q\n' "$DNS"
    printf 'MTU=%q\n' "$MTU"
    printf 'AUTOSTART=%q\n' "$AUTOSTART"
    printf 'FIREWALL=%q\n' "$FIREWALL"
    printf 'BLOCK_PING=%q\n' "$BLOCK_PING"
    printf 'IPV6_PRIORITY=%q\n' "$IPV6_PRIORITY"
    printf 'EXIT_MODE=%q\n' "$EXIT_MODE"
  } > "$tmp"

  install -m 600 "$tmp" "$CONFIG_FILE"
  rm -f "$tmp"
}

value_or_empty() {
  local value="${1:-}"
  if [[ -n "$value" ]]; then
    printf "%s" "$value"
  else
    printf "未配置"
  fi
}

yes_no_label() {
  case "${1:-0}" in
    1|yes|Yes|Y|y|true|TRUE) printf "Yes" ;;
    *) printf "No" ;;
  esac
}

enabled_label() {
  case "${1:-0}" in
    1|yes|Yes|Y|y|true|TRUE) printf "已启用" ;;
    *) printf "未启用" ;;
  esac
}

print_config() {
  printf "SERVER_IPV4：%s\n" "$(value_or_empty "$SERVER_IPV4")"
  printf "CLIENT_IPV4：%s\n" "$(value_or_empty "$CLIENT_IPV4")"
  printf "SERVER_IPV6：%s\n" "$(value_or_empty "$SERVER_IPV6")"
  printf "CLIENT_IPV6：%s\n" "$(value_or_empty "$CLIENT_IPV6")"
  printf "ROUTED64：%s\n" "$(value_or_empty "$ROUTED64")"
  printf "ROUTED48：%s\n" "$(value_or_empty "$ROUTED48")"
  printf "EXIT_MODE：%s\n" "$(exit_mode_label)"
  printf "EXIT_IPV6：%s\n" "$(get_configured_exit_ipv6)"
  printf "DNS：%s\n" "$(value_or_empty "$DNS")"
  printf "MTU：%s\n" "$(value_or_empty "$MTU")"
  printf "AUTOSTART：%s\n" "$(yes_no_label "$AUTOSTART")"
  printf "FIREWALL：%s\n" "$(enabled_label "$FIREWALL")"
  printf "BLOCK_PING：%s\n" "$(enabled_label "$BLOCK_PING")"
  printf "IPV6_PRIORITY：%s\n" "$(priority_label)"
}

check_required_config() {
  local missing=0
  local name value

  for name in SERVER_IPV4 CLIENT_IPV4 SERVER_IPV6 CLIENT_IPV6; do
    value="${!name:-}"
    if [[ -z "$value" ]]; then
      print_err "缺少必填配置：$name"
      missing=1
    fi
  done

  if [[ -z "${MTU:-}" ]]; then
    print_err "缺少必填配置：MTU"
    missing=1
  fi

  if [[ "${EXIT_MODE:-48}" == "48" && -z "${ROUTED48:-}" ]]; then
    print_err "缺少 Routed /48 配置；当前出口模式为 Routed /48。"
    missing=1
  fi

  if [[ "${EXIT_MODE:-48}" == "64" && -z "${ROUTED64:-}" ]]; then
    print_err "缺少 Routed /64 配置；当前出口模式为 Routed /64。"
    missing=1
  fi

  if [[ "$missing" -ne 0 ]]; then
    print_err "请先创建 HE 隧道或补全 $CONFIG_FILE。"
    return 1
  fi
}

strip_prefix() {
  local value="${1:-}"
  printf "%s" "${value%%/*}"
}

ensure_ipv6_prefix() {
  local value="${1:-}"
  local prefix="${2:-64}"

  if [[ "$value" == */* ]]; then
    printf "%s" "$value"
  else
    printf "%s/%s" "$value" "$prefix"
  fi
}

normalize_exit_mode() {
  case "${EXIT_MODE:-48}" in
    64|Routed64|routed64|ROUTED64|/64) printf "64" ;;
    *) printf "48" ;;
  esac
}

exit_mode_label() {
  case "$(normalize_exit_mode)" in
    64) printf "Routed /64" ;;
    *) printf "Routed /48" ;;
  esac
}

normalize_ipv6_priority() {
  case "${IPV6_PRIORITY:-he}" in
    native|Native|system|SYSTEM|原生|系统原生) printf "native" ;;
    *) printf "he" ;;
  esac
}

priority_label() {
  case "$(normalize_ipv6_priority)" in
    native) printf "系统原生 IPv6 优先" ;;
    *) printf "HE 隧道 IPv6 优先" ;;
  esac
}

he_route_metric() {
  case "$(normalize_ipv6_priority)" in
    native) printf "4096" ;;
    *) printf "1" ;;
  esac
}

routed64_exit_ip() {
  local prefix="${ROUTED64%%/*}"
  prefix="${prefix%::}"
  if [[ -z "$prefix" ]]; then
    return 1
  fi
  printf "%s::1" "$prefix"
}

expand_ipv6_to_hextets_basic() {
  local input="${1:-}"
  local addr="${input%%/*}"
  local left=""
  local right=""
  local missing=0
  local i=0
  local parts=()
  local left_parts=()
  local right_parts=()

  if [[ -z "$addr" ]]; then
    return 1
  fi

  if [[ "$addr" == *::* ]]; then
    left="${addr%%::*}"
    right="${addr##*::}"
    if [[ -n "$left" ]]; then IFS=':' read -r -a left_parts <<< "$left"; fi
    if [[ -n "$right" ]]; then IFS=':' read -r -a right_parts <<< "$right"; fi
    missing=$((8 - ${#left_parts[@]} - ${#right_parts[@]}))
    if (( missing < 0 )); then return 1; fi
    parts=("${left_parts[@]}")
    for ((i=0; i<missing; i++)); do parts+=("0"); done
    parts+=("${right_parts[@]}")
  else
    IFS=':' read -r -a parts <<< "$addr"
  fi

  if (( ${#parts[@]} != 8 )); then return 1; fi
  printf "%s\n" "${parts[@]}"
}

routed48_exit_ip() {
  local prefix="${ROUTED48:-}"
  local parts=()
  if [[ -z "$prefix" ]]; then
    return 1
  fi
  if ! mapfile -t parts < <(expand_ipv6_to_hextets_basic "$prefix"); then
    return 1
  fi
  printf "%s:%s:%s:1::1" "${parts[0]}" "${parts[1]}" "${parts[2]}"
}

get_configured_exit_ipv6() {
  case "$(normalize_exit_mode)" in
    64) routed64_exit_ip 2>/dev/null || printf "未配置" ;;
    *) routed48_exit_ip 2>/dev/null || printf "未配置" ;;
  esac
}

remove_known_exit_addresses() {
  local ip64="" ip48=""
  ip64="$(routed64_exit_ip 2>/dev/null || true)"
  ip48="$(routed48_exit_ip 2>/dev/null || true)"
  if [[ -n "$ip64" && "$ip64" != "未配置" ]]; then
    ip -6 addr del "$ip64/64" dev "$TUNNEL_NAME" >/dev/null 2>&1 || true
  fi
  if [[ -n "$ip48" && "$ip48" != "未配置" && "$ip48" != "$ip64" ]]; then
    ip -6 addr del "$ip48/64" dev "$TUNNEL_NAME" >/dev/null 2>&1 || true
  fi
}

apply_exit_route() {
  require_root || return 1
  if ! tunnel_exists; then
    print_err "隧道接口不存在，无法配置出口 IPv6。"
    return 1
  fi

  local exit_ip
  exit_ip="$(get_configured_exit_ipv6)"
  if [[ -z "$exit_ip" || "$exit_ip" == "未配置" ]]; then
    print_err "无法生成出口 IPv6，请检查 ROUTED64/ROUTED48 与 EXIT_MODE。"
    return 1
  fi

  remove_known_exit_addresses

  if ! ip -6 addr replace "$exit_ip/64" dev "$TUNNEL_NAME"; then
    print_err "添加出口 IPv6 失败：$exit_ip/64"
    return 1
  fi

  local metric
  metric="$(he_route_metric)"

  ip -6 route del default dev "$TUNNEL_NAME" >/dev/null 2>&1 || true

  if ! ip -6 route replace default dev "$TUNNEL_NAME" src "$exit_ip" metric "$metric"; then
    print_err "设置默认 IPv6 路由失败：default dev $TUNNEL_NAME src $exit_ip metric $metric"
    return 1
  fi

  print_ok "出口模式：$(exit_mode_label)"
  print_ok "出口 IPv6：$exit_ip"
  print_ok "IPv6 优先级：$(priority_label)，HE 默认路由 metric=$metric"
}


remove_block_ping_rules() {
  if ! has_cmd ip6tables; then
    return 0
  fi

  local ip64="" ip48="" ip=""
  ip64="$(routed64_exit_ip 2>/dev/null || true)"
  ip48="$(routed48_exit_ip 2>/dev/null || true)"

  for ip in "$ip64" "$ip48"; do
    [[ -z "$ip" || "$ip" == "未配置" ]] && continue
    while ip6tables -C INPUT -i "$TUNNEL_NAME" -p ipv6-icmp --icmpv6-type echo-request -d "$ip/128" -j DROP >/dev/null 2>&1; do
      ip6tables -D INPUT -i "$TUNNEL_NAME" -p ipv6-icmp --icmpv6-type echo-request -d "$ip/128" -j DROP >/dev/null 2>&1 || break
    done
  done
}

apply_block_ping_rules() {
  require_root || return 1

  if ! has_cmd ip6tables; then
    print_warn "未检测到 ip6tables，无法配置禁止 Ping 规则。"
    return 1
  fi

  if ! tunnel_exists; then
    print_warn "隧道接口不存在，禁止 Ping 配置已保存，创建隧道后会自动应用。"
    return 0
  fi

  local exit_ip
  exit_ip="$(get_configured_exit_ipv6)"
  if [[ -z "$exit_ip" || "$exit_ip" == "未配置" ]]; then
    print_warn "出口 IPv6 未配置，无法添加禁止 Ping 规则。"
    return 1
  fi

  remove_block_ping_rules

  if [[ "${BLOCK_PING:-1}" == "1" ]]; then
    ip6tables -I INPUT 1 -i "$TUNNEL_NAME" -p ipv6-icmp --icmpv6-type echo-request -d "$exit_ip/128" -j DROP >/dev/null 2>&1 || true
    print_ok "已禁止外部 Ping 当前 HE 出口 IPv6：$exit_ip"
  else
    print_ok "已允许外部 Ping 当前 HE 出口 IPv6。"
  fi
}

enable_block_ping() {
  require_root || return 1
  load_config
  BLOCK_PING="1"
  save_config || return 1
  apply_block_ping_rules
}

disable_block_ping() {
  require_root || return 1
  load_config
  BLOCK_PING="0"
  save_config || return 1
  apply_block_ping_rules
}


tunnel_exists() {
  has_cmd ip && ip link show dev "$TUNNEL_NAME" >/dev/null 2>&1
}

tunnel_is_connected() {
  if ! tunnel_exists; then
    return 1
  fi

  if ip -6 route show default 2>/dev/null | grep -q "$TUNNEL_NAME"; then
    return 0
  fi

  return 1
}

get_tunnel_status() {
  if tunnel_is_connected; then
    printf "已连接"
  else
    printf "未连接"
  fi
}

current_mtu() {
  local mtu=""
  if tunnel_exists; then
    mtu="$(ip -o link show dev "$TUNNEL_NAME" 2>/dev/null | awk '{for(i=1;i<=NF;i++) if($i=="mtu") {print $(i+1); exit}}')"
  fi

  if [[ -n "$mtu" ]]; then
    printf "%s" "$mtu"
  elif [[ -n "${MTU:-}" ]]; then
    printf "%s" "$MTU"
  else
    printf "1280"
  fi
}

get_exit_ipv6() {
  # 状态页显示配置生成的真实业务出口，不显示 Tunnel Client IPv6。
  get_configured_exit_ipv6
}

curl_exit_ipv6() {
  local exit_ip=""
  local detected=""

  exit_ip="$(get_configured_exit_ipv6)"
  if [[ -z "$exit_ip" || "$exit_ip" == "未配置" ]]; then
    printf "未获取"
    return 0
  fi

  if has_cmd curl; then
    detected="$(curl -6 -s --interface "$exit_ip" --connect-timeout 4 --max-time 8 ip.sb 2>/dev/null | tr -d '[:space:]')"
    if [[ -z "$detected" ]]; then
      detected="$(curl -6 -s --connect-timeout 4 --max-time 8 ip.sb 2>/dev/null | tr -d '[:space:]')"
    fi
  elif has_cmd wget; then
    detected="$(timeout 8 wget -qO- -6 https://ip.sb 2>/dev/null | tr -d '[:space:]')"
  fi

  if [[ -n "$detected" ]]; then
    printf "%s" "$detected"
  else
    printf "未获取"
  fi
}

autostart_status() {
  if has_cmd systemctl && systemctl is-enabled "$SERVICE_NAME" >/dev/null 2>&1; then
    printf "已启用"
  else
    printf "未启用"
  fi
}

dns_servers_array() {
  case "${DNS:-Cloudflare}" in
    HE|"HE DNS")
      printf "2001:470:20::2 74.82.42.42"
      ;;
    Google|"Google DNS")
      printf "2001:4860:4860::8888 2001:4860:4860::8844"
      ;;
    Cloudflare|"Cloudflare DNS"|*)
      printf "2606:4700:4700::1111 2606:4700:4700::1001"
      ;;
  esac
}

apply_dns() {
  local servers_text
  local servers=()
  local server

  servers_text="$(dns_servers_array)"
  # shellcheck disable=SC2206
  servers=($servers_text)

  if [[ "${#servers[@]}" -eq 0 ]]; then
    return 0
  fi

  if ! tunnel_exists; then
    print_warn "隧道接口不存在，DNS 配置已保存，暂未应用到接口。"
    return 0
  fi

  if has_cmd resolvectl; then
    resolvectl dns "$TUNNEL_NAME" "${servers[@]}" >/dev/null 2>&1 || true
    resolvectl domain "$TUNNEL_NAME" "~." >/dev/null 2>&1 || true
    print_ok "DNS 已应用到接口 $TUNNEL_NAME：${servers_text}"
  elif has_cmd systemd-resolve; then
    for server in "${servers[@]}"; do
      systemd-resolve --interface="$TUNNEL_NAME" --set-dns="$server" >/dev/null 2>&1 || true
    done
    systemd-resolve --interface="$TUNNEL_NAME" --set-domain="~." >/dev/null 2>&1 || true
    print_ok "DNS 已应用到接口 $TUNNEL_NAME：${servers_text}"
  else
    print_warn "未检测到 resolvectl/systemd-resolve，DNS 配置已保存但未自动写入系统解析器。"
  fi
}

down_tunnel_quiet() {
  if ! has_cmd ip; then
    return 0
  fi

  if tunnel_exists; then
    ip -6 route del default dev "$TUNNEL_NAME" >/dev/null 2>&1 || true
    ip link set "$TUNNEL_NAME" down >/dev/null 2>&1 || true
    ip tunnel del "$TUNNEL_NAME" >/dev/null 2>&1 || true
  fi
}

down_tunnel() {
  require_root || return 1

  printf "正在删除隧道接口 %s...\n" "$TUNNEL_NAME"
  down_tunnel_quiet

  if tunnel_exists; then
    print_err "隧道删除失败，请检查 ip tunnel 状态。"
    return 1
  fi

  print_ok "HE 隧道已删除。"
}

apply_tunnel() {
  require_root || return 1
  load_config
  check_required_config || return 1

  if ! has_cmd ip; then
    print_err "未检测到 ip 命令，请先安装 iproute2。"
    return 1
  fi

  if has_cmd modprobe; then
    modprobe sit >/dev/null 2>&1 || true
  fi

  local client_addr

  client_addr="$(ensure_ipv6_prefix "$CLIENT_IPV6" 64)"

  printf "\n正在创建/重建 HE 隧道：%s\n" "$TUNNEL_NAME"

  down_tunnel_quiet

  printf "[1/5] 创建 SIT 隧道...\n"
  if ! ip tunnel add "$TUNNEL_NAME" mode sit remote "$SERVER_IPV4" local "$CLIENT_IPV4" ttl 255; then
    print_err "创建 SIT 隧道失败。请确认 IPv4、协议 41、防火墙和 HE Tunnel Broker 配置。"
    return 1
  fi

  printf "[2/5] 设置 MTU...\n"
  if ! ip link set dev "$TUNNEL_NAME" mtu "$MTU"; then
    print_err "设置 MTU 失败。"
    down_tunnel_quiet
    return 1
  fi

  printf "[3/5] 启动接口并添加 IPv6 地址...\n"
  if ! ip link set dev "$TUNNEL_NAME" up; then
    print_err "启动隧道接口失败。"
    down_tunnel_quiet
    return 1
  fi

  if ! ip -6 addr add "$client_addr" dev "$TUNNEL_NAME"; then
    print_err "添加 Client IPv6 失败：$client_addr"
    down_tunnel_quiet
    return 1
  fi

  printf "[4/5] 添加 Routed 出口 IPv6 并设置默认路由...\n"
  if ! apply_exit_route; then
    down_tunnel_quiet
    return 1
  fi

  sysctl -w net.ipv6.conf.all.forwarding=1 >/dev/null 2>&1 || true

  printf "[5/5] 应用 DNS 与防火墙配置...\n"
  apply_dns

  if [[ "${FIREWALL:-0}" == "1" ]]; then
    enable_firewall_rules
  fi

  apply_block_ping_rules || true

  print_ok "HE 隧道配置完成。"
}

ask_required() {
  local prompt="$1"
  local var_name="$2"
  local default="${3:-}"
  local input=""

  while true; do
    if [[ -n "$default" ]]; then
      printf "%s（当前/默认：%s）" "$prompt" "$default"
    else
      printf "%s" "$prompt"
    fi
    IFS= read -r input || input=""
    input="${input:-$default}"

    if [[ -n "${input//[[:space:]]/}" ]]; then
      printf -v "$var_name" "%s" "$input"
      return 0
    fi

    print_warn "输入不能为空，请重新输入。"
  done
}
ask_optional() {
  local prompt="$1"
  local var_name="$2"
  local default="${3:-}"
  local input=""

  if [[ -n "$default" ]]; then
    printf "%s（当前/默认：%s）" "$prompt" "$default"
  else
    printf "%s" "$prompt"
  fi
  IFS= read -r input || input=""
  input="${input:-$default}"
  printf -v "$var_name" "%s" "$input"
}
ask_dns() {
  local var_name="$1"
  local current="${2:-Cloudflare}"
  local choice=""
  local default_dns="$current"

  case "$default_dns" in
    HE|"HE DNS") default_dns="HE" ;;
    Google|"Google DNS") default_dns="Google" ;;
    Cloudflare|"Cloudflare DNS"|"") default_dns="Cloudflare" ;;
    *) default_dns="Cloudflare" ;;
  esac

  while true; do
    printf "请选择 DNS：

"
    printf "1. HE DNS
"
    printf "2. Cloudflare DNS
"
    printf "3. Google DNS

"
    printf "请输入（当前/默认：%s）：" "$default_dns"
    IFS= read -r choice || choice=""

    case "$choice" in
      1)
        printf -v "$var_name" "%s" "HE"
        return 0
        ;;
      2)
        printf -v "$var_name" "%s" "Cloudflare"
        return 0
        ;;
      3)
        printf -v "$var_name" "%s" "Google"
        return 0
        ;;
      "")
        printf -v "$var_name" "%s" "$default_dns"
        return 0
        ;;
      HE|Cloudflare|Google)
        printf -v "$var_name" "%s" "$choice"
        return 0
        ;;
      *)
        print_warn "请输入 1、2 或 3。"
        ;;
    esac
  done
}
ask_exit_mode() {
  local var_name="$1"
  local current="${2:-48}"
  local choice=""

  case "$current" in
    64|Routed64|routed64|ROUTED64|/64) current="64" ;;
    *) current="48" ;;
  esac

  while true; do
    printf "请选择 IPv6 出口模式：

"
    printf "1. Routed /64
"
    printf "2. Routed /48（推荐，默认）

"
    printf "请输入（当前/默认：Routed /%s）：" "$current"
    IFS= read -r choice || choice=""

    case "$choice" in
      1|64|/64)
        printf -v "$var_name" "%s" "64"
        return 0
        ;;
      2|48|/48|"")
        printf -v "$var_name" "%s" "48"
        return 0
        ;;
      *)
        print_warn "请输入 1 或 2。"
        ;;
    esac
  done
}
ask_ipv6_priority() {
  local var_name="$1"
  local current="${2:-he}"
  local choice=""

  case "$current" in
    native|Native|system|SYSTEM|原生|系统原生) current="native" ;;
    *) current="he" ;;
  esac

  while true; do
    printf "请选择系统 IPv6 出口优先级：

"
    printf "1. HE 隧道 IPv6 优先（推荐，默认）
"
    printf "2. 系统原生 IPv6 优先

"
    printf "请输入（当前/默认：%s）：" "$(if [[ "$current" == "native" ]]; then printf "系统原生 IPv6 优先"; else printf "HE 隧道 IPv6 优先"; fi)"
    IFS= read -r choice || choice=""

    case "$choice" in
      1|he|HE|"")
        printf -v "$var_name" "%s" "he"
        return 0
        ;;
      2|native|Native|system|SYSTEM)
        printf -v "$var_name" "%s" "native"
        return 0
        ;;
      *)
        print_warn "请输入 1 或 2。"
        ;;
    esac
  done
}

ask_mtu() {
  local var_name="$1"
  local default="${2:-1280}"
  local input=""

  while true; do
    printf "请输入 MTU（默认：%s）：" "$default"
    IFS= read -r input || input=""
    input="${input:-$default}"

    if [[ "$input" =~ ^[0-9]+$ ]] && (( input >= 1280 && input <= 1480 )); then
      printf -v "$var_name" "%s" "$input"
      return 0
    fi

    print_warn "MTU 建议范围为 1280-1480，请重新输入。"
  done
}
ask_yes_no() {
  local prompt="$1"
  local var_name="$2"
  local default="${3:-N}"
  local input=""

  while true; do
    printf "%s（Y/N，默认：%s）：" "$prompt" "$default"
    IFS= read -r input || input=""
    input="${input:-$default}"

    case "$input" in
      y|Y|yes|YES|Yes)
        printf -v "$var_name" "%s" "1"
        return 0
        ;;
      n|N|no|NO|No)
        printf -v "$var_name" "%s" "0"
        return 0
        ;;
      *)
        print_warn "请输入 Y 或 N。"
        ;;
    esac
  done
}
confirm_action() {
  local prompt="$1"
  local default="${2:-N}"
  local answer="0"

  ask_yes_no "$prompt" answer "$default"
  [[ "$answer" == "1" ]]
}

enable_autostart() {
  require_root || return 1

  AUTOSTART="1"
  save_config || return 1

  if ! has_cmd systemctl; then
    print_warn "未检测到 systemctl，已保存 AUTOSTART=1，但无法启用 systemd 服务。"
    return 0
  fi

  systemctl daemon-reload >/dev/null 2>&1 || true

  if systemctl enable "$SERVICE_NAME" >/dev/null 2>&1; then
    print_ok "开机自启已启用。"
  else
    print_err "开机自启启用失败，请检查 /etc/systemd/system/${SERVICE_NAME}。"
    return 1
  fi
}

disable_autostart() {
  require_root || return 1

  AUTOSTART="0"
  save_config || return 1

  if has_cmd systemctl; then
    systemctl disable "$SERVICE_NAME" >/dev/null 2>&1 || true
    systemctl daemon-reload >/dev/null 2>&1 || true
  fi

  print_ok "开机自启已关闭。"
}

show_config_confirmation() {
  printf "=================================\n"
  printf "配置确认\n"
  printf "=================================\n\n"

  printf "Tunnel Server IPv4：\n%s\n\n" "$(value_or_empty "$SERVER_IPV4")"
  printf "Tunnel Client IPv4：\n%s\n\n" "$(value_or_empty "$CLIENT_IPV4")"
  printf "Tunnel Server IPv6：\n%s\n\n" "$(value_or_empty "$SERVER_IPV6")"
  printf "Tunnel Client IPv6：\n%s\n\n" "$(value_or_empty "$CLIENT_IPV6")"
  printf "Routed /64：\n%s\n\n" "$(value_or_empty "$ROUTED64")"
  printf "Routed /48：\n%s\n\n" "$(value_or_empty "$ROUTED48")"
  printf "DNS：\n%s\n\n" "$(value_or_empty "$DNS")"
  printf "MTU：\n%s\n\n" "$(value_or_empty "$MTU")"
  printf "开机自启：\n%s\n\n" "$(yes_no_label "$AUTOSTART")"
}

create_tunnel_interactive() {
  require_root || { pause; return 1; }

  load_config
  clear_screen
  printf "=================================\n"
  printf "创建 HE 隧道\n"
  printf "=================================\n\n"

  ask_required "请输入 Tunnel Server IPv4：" SERVER_IPV4 "$SERVER_IPV4"
  ask_required "请输入 Tunnel Client IPv4：" CLIENT_IPV4 "$CLIENT_IPV4"
  ask_required "请输入 Tunnel Server IPv6：" SERVER_IPV6 "$SERVER_IPV6"
  ask_required "请输入 Tunnel Client IPv6：" CLIENT_IPV6 "$CLIENT_IPV6"
  ask_required "请输入 Routed /64：" ROUTED64 "$ROUTED64"
  ask_optional "请输入 Routed /48：" ROUTED48 "$ROUTED48"
  ask_exit_mode EXIT_MODE "$EXIT_MODE"
  ask_ipv6_priority IPV6_PRIORITY "$IPV6_PRIORITY"
  ask_yes_no "是否禁止外部 Ping HE 出口 IPv6？" BLOCK_PING "Y"
  ask_dns DNS "$DNS"
  ask_mtu MTU "${MTU:-1280}"
  ask_yes_no "是否启用开机自启？" AUTOSTART "$(if [[ "${AUTOSTART:-0}" == "1" ]]; then printf "Y"; else printf "N"; fi)"

  clear_screen
  show_config_confirmation

  if confirm_action "确认创建？" "N"; then
    save_config || { pause; return 1; }
    apply_tunnel
    if [[ "$AUTOSTART" == "1" ]]; then
      enable_autostart
    else
      disable_autostart
    fi
  else
    print_warn "已取消创建。"
  fi

  pause
}

delete_tunnel_interactive() {
  require_root || { pause; return 1; }

  load_config
  clear_screen
  printf "=================================\n"
  printf "删除 HE 隧道\n"
  printf "=================================\n\n"

  if ! confirm_action "确认删除当前 HE 隧道？" "N"; then
    print_warn "已取消删除。"
    pause
    return 0
  fi

  down_tunnel
  disable_autostart

  if confirm_action "是否同时删除配置文件？" "N"; then
    rm -f "$CONFIG_FILE"
    print_ok "配置文件已删除：$CONFIG_FILE"
  else
    print_warn "配置文件已保留：$CONFIG_FILE"
  fi

  pause
}

modify_tunnel_interactive() {
  require_root || { pause; return 1; }

  while true; do
    load_config
    clear_screen
    printf "=================================\n"
    printf "修改 HE 隧道\n"
    printf "=================================\n\n"
    printf "当前配置：\n\n"
    print_config

    printf "\n1. 修改 Tunnel Server IPv4\n"
    printf "2. 修改 Tunnel Client IPv4\n"
    printf "3. 修改 Server IPv6\n"
    printf "4. 修改 Client IPv6\n"
    printf "5. 修改 Routed /64\n"
    printf "6. 修改 Routed /48\n"
    printf "7. 修改 IPv6 出口模式\n"
    printf "8. 修改 IPv6 优先级\n"
    printf "9. 修改禁止外部 Ping\n"
    printf "10. 修改 DNS\n"
    printf "11. 修改 MTU\n"
    printf "12. 返回\n\n"
    printf "请选择："

    local choice=""
    IFS= read -r choice || choice=""

    case "$choice" in
      1)
        ask_required "请输入新的 Tunnel Server IPv4：" SERVER_IPV4 "$SERVER_IPV4"
        ;;
      2)
        ask_required "请输入新的 Tunnel Client IPv4：" CLIENT_IPV4 "$CLIENT_IPV4"
        ;;
      3)
        ask_required "请输入新的 Server IPv6：" SERVER_IPV6 "$SERVER_IPV6"
        ;;
      4)
        ask_required "请输入新的 Client IPv6：" CLIENT_IPV6 "$CLIENT_IPV6"
        ;;
      5)
        ask_required "请输入新的 Routed /64：" ROUTED64 "$ROUTED64"
        ;;
      6)
        ask_optional "请输入新的 Routed /48：" ROUTED48 "$ROUTED48"
        ;;
      7)
        ask_exit_mode EXIT_MODE "$EXIT_MODE"
        save_config || { pause; continue; }
        if tunnel_exists; then
          printf "\n正在切换出口模式，无需重建隧道...\n"
          apply_exit_route
          pause
          continue
        fi
        ;;
      8)
        ask_ipv6_priority IPV6_PRIORITY "$IPV6_PRIORITY"
        save_config || { pause; continue; }
        if tunnel_exists; then
          printf "\n正在切换 IPv6 优先级...\n"
          apply_exit_route
          pause
          continue
        fi
        ;;
      9)
        ask_yes_no "是否禁止外部 Ping HE 出口 IPv6？" BLOCK_PING "$(if [[ "${BLOCK_PING:-1}" == "1" ]]; then printf "Y"; else printf "N"; fi)"
        save_config || { pause; continue; }
        apply_block_ping_rules
        pause
        continue
        ;;
      10)
        ask_dns DNS "$DNS"
        ;;
      11)
        ask_mtu MTU "$MTU"
        ;;
      12)
        return 0
        ;;
      *)
        print_warn "无效选择。"
        pause
        continue
        ;;
    esac

    save_config || { pause; continue; }
    printf "\n配置已保存，正在自动重建隧道...\n"
    apply_tunnel
    pause
  done
}

show_status_and_config() {
  load_config
  clear_screen
  printf "=================================
"
  printf "隧道状态与当前配置
"
  printf "=================================

"

  printf "当前隧道状态：%s
" "$(get_tunnel_status)"
  printf "当前出口模式：%s
" "$(exit_mode_label)"
  printf "当前出口 IPv6：%s
" "$(get_exit_ipv6)"
  printf "curl 检测出口：%s
" "$(curl_exit_ipv6)"
  printf "当前 MTU：%s
" "$(current_mtu)"
  printf "IPv6 优先级：%s
" "$(priority_label)"
  printf "禁止外部 Ping：%s
" "$(enabled_label "$BLOCK_PING")"
  printf "开机自启：%s

" "$(autostart_status)"

  printf "当前配置：

"
  print_config

  if tunnel_exists; then
    printf "
接口信息：
"
    ip -brief addr show dev "$TUNNEL_NAME" 2>/dev/null || true
    printf "
IPv6 路由：
"
    ip -6 route show dev "$TUNNEL_NAME" 2>/dev/null || true
  else
    printf "
接口信息：%s 不存在。
" "$TUNNEL_NAME"
  fi

  pause
}

show_exit_ipv6() {
  load_config
  clear_screen
  printf "=================================
"
  printf "查看出口 IPv6
"
  printf "=================================

"
  printf "当前出口模式：%s
" "$(exit_mode_label)"
  printf "配置出口 IPv6：%s
" "$(get_exit_ipv6)"
  printf "执行：curl -6 --interface $(get_exit_ipv6) ip.sb

"
  printf "curl 检测出口：%s
" "$(curl_exit_ipv6)"
  pause
}

test_connectivity() {
  load_config
  clear_screen
  printf "=================================\n"
  printf "测试连通性\n"
  printf "=================================\n\n"

  if ! tunnel_exists; then
    print_warn "隧道接口不存在，请先创建 HE 隧道。"
    pause
    return 0
  fi

  local ping_cmd=""
  if has_cmd ping; then
    ping_cmd="ping"
  elif has_cmd ping6; then
    ping_cmd="ping6"
  else
    print_err "未检测到 ping/ping6。"
    pause
    return 1
  fi

  local server_addr
  server_addr="$(strip_prefix "$SERVER_IPV6")"

  if [[ -n "$server_addr" ]]; then
    printf "\n[1/3] 测试 HE Server IPv6：%s\n" "$server_addr"
    if [[ "$ping_cmd" == "ping" ]]; then
      ping -6 -c 3 -W 2 "$server_addr" || true
    else
      ping6 -c 3 -W 2 "$server_addr" || true
    fi
  fi

  printf "\n[2/3] 测试 Google IPv6 DNS：2001:4860:4860::8888\n"
  if [[ "$ping_cmd" == "ping" ]]; then
    ping -6 -c 3 -W 2 2001:4860:4860::8888 || true
  else
    ping6 -c 3 -W 2 2001:4860:4860::8888 || true
  fi

  printf "\n[3/3] 测试 Cloudflare IPv6 DNS：2606:4700:4700::1111\n"
  if [[ "$ping_cmd" == "ping" ]]; then
    ping -6 -c 3 -W 2 2606:4700:4700::1111 || true
  else
    ping6 -c 3 -W 2 2606:4700:4700::1111 || true
  fi

  printf "\n出口 IPv6：%s\n" "$(get_exit_ipv6)"
  pause
}

dns_menu() {
  require_root || { pause; return 1; }

  load_config
  clear_screen
  printf "=================================\n"
  printf "DNS 设置\n"
  printf "=================================\n\n"
  printf "当前 DNS：%s\n\n" "$(value_or_empty "$DNS")"

  ask_dns DNS "$DNS"
  save_config || { pause; return 1; }
  apply_dns

  pause
}

mtu_menu() {
  require_root || { pause; return 1; }

  load_config
  clear_screen
  printf "=================================\n"
  printf "MTU 设置\n"
  printf "=================================\n\n"
  printf "当前 MTU：%s\n\n" "$(current_mtu)"

  ask_mtu MTU "$MTU"
  save_config || { pause; return 1; }

  if tunnel_exists; then
    ip link set dev "$TUNNEL_NAME" mtu "$MTU" && print_ok "MTU 已应用到 $TUNNEL_NAME：$MTU"
  else
    print_warn "隧道接口不存在，MTU 已保存，创建隧道时会自动应用。"
  fi

  pause
}

enable_firewall_rules() {
  require_root || return 1

  if ! has_cmd ip6tables; then
    print_warn "未检测到 ip6tables，无法配置 IPv6 防火墙。"
    return 1
  fi

  ip6tables -N "$FIREWALL_CHAIN" >/dev/null 2>&1 || true
  ip6tables -F "$FIREWALL_CHAIN" >/dev/null 2>&1 || true

  ip6tables -A "$FIREWALL_CHAIN" -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT >/dev/null 2>&1 || true
  if [[ "${BLOCK_PING:-1}" == "1" ]]; then
    local exit_ip
    exit_ip="$(get_configured_exit_ipv6)"
    if [[ -n "$exit_ip" && "$exit_ip" != "未配置" ]]; then
      ip6tables -A "$FIREWALL_CHAIN" -p ipv6-icmp --icmpv6-type echo-request -d "$exit_ip/128" -j DROP >/dev/null 2>&1 || true
    fi
  fi
  ip6tables -A "$FIREWALL_CHAIN" -p ipv6-icmp -j ACCEPT >/dev/null 2>&1 || true
  ip6tables -A "$FIREWALL_CHAIN" -p tcp --dport 22 -j ACCEPT >/dev/null 2>&1 || true
  ip6tables -A "$FIREWALL_CHAIN" -j DROP >/dev/null 2>&1 || true

  if ! ip6tables -C INPUT -i "$TUNNEL_NAME" -j "$FIREWALL_CHAIN" >/dev/null 2>&1; then
    ip6tables -I INPUT 1 -i "$TUNNEL_NAME" -j "$FIREWALL_CHAIN" >/dev/null 2>&1 || true
  fi

  FIREWALL="1"
  save_config || true
  apply_block_ping_rules || true
  print_ok "基础 IPv6 防火墙已启用：允许已建立连接、必要 ICMPv6、SSH(22)，其余从 $TUNNEL_NAME 进入的入站流量将被丢弃。"
}

disable_firewall_rules() {
  require_root || return 1

  if has_cmd ip6tables; then
    while ip6tables -C INPUT -i "$TUNNEL_NAME" -j "$FIREWALL_CHAIN" >/dev/null 2>&1; do
      ip6tables -D INPUT -i "$TUNNEL_NAME" -j "$FIREWALL_CHAIN" >/dev/null 2>&1 || break
    done

    ip6tables -F "$FIREWALL_CHAIN" >/dev/null 2>&1 || true
    ip6tables -X "$FIREWALL_CHAIN" >/dev/null 2>&1 || true
  fi

  FIREWALL="0"
  save_config || true
  print_ok "基础 IPv6 防火墙已关闭。"
}

firewall_menu() {
  require_root || { pause; return 1; }

  while true; do
    load_config
    clear_screen
    printf "=================================
"
    printf "IPv6 防火墙
"
    printf "=================================

"
    printf "基础防火墙：%s
" "$(enabled_label "$FIREWALL")"
    printf "禁止外部 Ping 出口 IPv6：%s

" "$(enabled_label "$BLOCK_PING")"
    printf "1. 开启基础 IPv6 防火墙
"
    printf "2. 关闭基础 IPv6 防火墙
"
    printf "3. 禁止外部 Ping 当前 HE 出口 IPv6
"
    printf "4. 允许外部 Ping 当前 HE 出口 IPv6
"
    printf "5. 查看当前 IPv6 防火墙规则
"
    printf "6. 返回

"
    printf "请选择："

    local choice=""
    IFS= read -r choice || choice=""

    case "$choice" in
      1)
        enable_firewall_rules
        pause
        ;;
      2)
        disable_firewall_rules
        pause
        ;;
      3)
        enable_block_ping
        pause
        ;;
      4)
        disable_block_ping
        pause
        ;;
      5)
        if has_cmd ip6tables; then
          ip6tables -S "$FIREWALL_CHAIN" 2>/dev/null || print_warn "未找到 ${FIREWALL_CHAIN} 规则链。"
          printf "
INPUT 中 HE 相关规则：
"
          ip6tables -S INPUT 2>/dev/null | grep -E "$FIREWALL_CHAIN|$TUNNEL_NAME" || true
        else
          print_warn "未检测到 ip6tables。"
        fi
        pause
        ;;
      6)
        return 0
        ;;
      *)
        print_warn "无效选择。"
        pause
        ;;
    esac
  done
}

ipv6_priority_menu() {
  require_root || { pause; return 1; }

  while true; do
    load_config
    clear_screen
    printf "=================================\n"
    printf "IPv6 优先级切换\n"
    printf "=================================\n\n"
    printf "当前优先级：%s\n" "$(priority_label)"
    printf "HE 出口 IPv6：%s\n\n" "$(get_exit_ipv6)"
    printf "说明：HE 优先会把 he-ipv6 默认路由 metric 设为 1；系统原生优先会把 he-ipv6 默认路由 metric 设为 4096，保留 HE 作为备用。\n\n"
    printf "1. HE 隧道 IPv6 优先（默认）\n"
    printf "2. 系统原生 IPv6 优先\n"
    printf "3. 查看当前 IPv6 默认路由\n"
    printf "4. 返回\n\n"
    printf "请选择："

    local choice=""
    IFS= read -r choice || choice=""

    case "$choice" in
      1)
        IPV6_PRIORITY="he"
        save_config || { pause; continue; }
        if tunnel_exists; then apply_exit_route; else print_warn "隧道接口不存在，配置已保存，创建隧道后生效。"; fi
        pause
        ;;
      2)
        IPV6_PRIORITY="native"
        save_config || { pause; continue; }
        if tunnel_exists; then apply_exit_route; else print_warn "隧道接口不存在，配置已保存，创建隧道后生效。"; fi
        pause
        ;;
      3)
        ip -6 route show default 2>/dev/null || true
        pause
        ;;
      4)
        return 0
        ;;
      *)
        print_warn "无效选择。"
        pause
        ;;
    esac
  done
}

autostart_menu() {
  require_root || { pause; return 1; }

  while true; do
    load_config
    clear_screen
    printf "=================================\n"
    printf "开机自启管理\n"
    printf "=================================\n\n"
    printf "systemd 状态：%s\n" "$(autostart_status)"
    printf "配置文件 AUTOSTART：%s\n\n" "$(yes_no_label "$AUTOSTART")"

    printf "1. 启用开机自启\n"
    printf "2. 关闭开机自启\n"
    printf "3. 立即重启 systemd 隧道服务\n"
    printf "4. 查看服务状态\n"
    printf "5. 返回\n\n"
    printf "请选择："

    local choice=""
    IFS= read -r choice || choice=""

    case "$choice" in
      1)
        save_config || true
        enable_autostart
        pause
        ;;
      2)
        disable_autostart
        pause
        ;;
      3)
        if has_cmd systemctl; then
          systemctl daemon-reload >/dev/null 2>&1 || true
          systemctl restart "$SERVICE_NAME"
        else
          print_warn "未检测到 systemctl。"
        fi
        pause
        ;;
      4)
        if has_cmd systemctl; then
          systemctl status "$SERVICE_NAME" --no-pager || true
        else
          print_warn "未检测到 systemctl。"
        fi
        pause
        ;;
      5)
        return 0
        ;;
      *)
        print_warn "无效选择。"
        pause
        ;;
    esac
  done
}

expand_ipv6_to_hextets() {
  local input="${1:-}"
  local addr="${input%%/*}"
  local left=""
  local right=""
  local missing=0
  local i=0
  local parts=()
  local left_parts=()
  local right_parts=()

  if [[ -z "$addr" ]]; then
    return 1
  fi

  if [[ "$addr" == *::* ]]; then
    left="${addr%%::*}"
    right="${addr##*::}"

    if [[ -n "$left" ]]; then
      IFS=':' read -r -a left_parts <<< "$left"
    fi
    if [[ -n "$right" ]]; then
      IFS=':' read -r -a right_parts <<< "$right"
    fi

    missing=$((8 - ${#left_parts[@]} - ${#right_parts[@]}))
    if (( missing < 0 )); then
      return 1
    fi

    parts=("${left_parts[@]}")
    for ((i=0; i<missing; i++)); do
      parts+=("0")
    done
    parts+=("${right_parts[@]}")
  else
    IFS=':' read -r -a parts <<< "$addr"
  fi

  if (( ${#parts[@]} != 8 )); then
    return 1
  fi

  printf "%s\n" "${parts[@]}"
}

ipv6_48_generator() {
  load_config
  clear_screen
  printf "=================================\n"
  printf "/48 IPv6 生成器\n"
  printf "=================================\n\n"

  local prefix="${ROUTED48:-}"
  local count="10"
  local start_hex="0"

  if [[ -z "$prefix" ]]; then
    ask_required "请输入 Routed /48：" prefix ""
  else
    ask_optional "请输入 Routed /48：" prefix "$prefix"
  fi

  printf "生成多少个 /64？默认：10："
  IFS= read -r count || count=""
  count="${count:-10}"

  if ! [[ "$count" =~ ^[0-9]+$ ]] || (( count < 1 || count > 65536 )); then
    print_warn "数量无效，已使用默认值 10。"
    count="10"
  fi

  printf "起始子网 ID（十六进制，默认 0）："
  IFS= read -r start_hex || start_hex=""
  start_hex="${start_hex:-0}"

  local parts=()
  if ! mapfile -t parts < <(expand_ipv6_to_hextets "$prefix"); then
    print_err "无法解析 /48 前缀：$prefix"
    pause
    return 1
  fi

  local h1="${parts[0]}"
  local h2="${parts[1]}"
  local h3="${parts[2]}"
  local start_dec=0
  local i=0
  local subnet=0

  if [[ "$start_hex" =~ ^0[xX][0-9a-fA-F]+$ ]]; then
    start_dec=$((start_hex))
  elif [[ "$start_hex" =~ ^[0-9a-fA-F]+$ ]]; then
    start_dec=$((16#$start_hex))
  else
    print_warn "起始子网 ID 无效，已使用 0。"
    start_dec=0
  fi

  printf "\n生成结果：\n\n"
  for ((i=0; i<count; i++)); do
    subnet=$((start_dec + i))
    if (( subnet > 65535 )); then
      break
    fi
    printf "%s:%s:%s:%x::/64\n" "$h1" "$h2" "$h3" "$subnet"
  done

  pause
}

fetch_file() {
  local url="$1"
  local output="$2"

  if has_cmd curl; then
    curl -fsSL "$url" -o "$output"
  elif has_cmd wget; then
    wget -qO "$output" "$url"
  else
    print_err "未检测到 curl 或 wget，无法下载更新。"
    return 1
  fi
}

update_script() {
  require_root || { pause; return 1; }

  clear_screen
  printf "=================================\n"
  printf "更新脚本\n"
  printf "=================================\n\n"

  if [[ -d "$INSTALL_DIR/.git" ]] && has_cmd git; then
    printf "检测到 Git 仓库，正在执行 git pull...\n"
    if git -C "$INSTALL_DIR" pull --ff-only; then
      chmod +x "$INSTALL_DIR/he.sh" "$INSTALL_DIR/install.sh" "$INSTALL_DIR/uninstall.sh" 2>/dev/null || true
      if has_cmd systemctl; then
        systemctl daemon-reload >/dev/null 2>&1 || true
      fi
      print_ok "更新完成。"
    else
      print_err "git pull 失败。"
    fi
    pause
    return 0
  fi

  if [[ -z "${GITHUB_REPO:-}" || "$GITHUB_REPO" != */* ]]; then
    print_err "GitHub 仓库地址配置异常：$GITHUB_REPO"
    pause
    return 1
  fi

  local tmp
  tmp="$(mktemp -d)" || return 1

  printf "正在从 GitHub 拉取最新版：%s\n\n" "$RAW_BASE"

  if ! fetch_file "$RAW_BASE/he.sh" "$tmp/he.sh"; then
    rm -rf "$tmp"
    pause
    return 1
  fi

  fetch_file "$RAW_BASE/install.sh" "$tmp/install.sh" || true
  fetch_file "$RAW_BASE/uninstall.sh" "$tmp/uninstall.sh" || true
  mkdir -p "$tmp/systemd" "$tmp/config"
  fetch_file "$RAW_BASE/systemd/he-tunnel.service" "$tmp/systemd/he-tunnel.service" || true
  fetch_file "$RAW_BASE/config/config.example.conf" "$tmp/config/config.example.conf" || true

  mkdir -p "$INSTALL_DIR" "$INSTALL_DIR/systemd" "$INSTALL_DIR/config"
  install -m 755 "$tmp/he.sh" "$INSTALL_DIR/he.sh"
  [[ -f "$tmp/install.sh" ]] && install -m 755 "$tmp/install.sh" "$INSTALL_DIR/install.sh"
  [[ -f "$tmp/uninstall.sh" ]] && install -m 755 "$tmp/uninstall.sh" "$INSTALL_DIR/uninstall.sh"
  [[ -f "$tmp/systemd/he-tunnel.service" ]] && install -m 644 "$tmp/systemd/he-tunnel.service" "/etc/systemd/system/$SERVICE_NAME"
  [[ -f "$tmp/config/config.example.conf" ]] && install -m 644 "$tmp/config/config.example.conf" "$INSTALL_DIR/config/config.example.conf"

  rm -rf "$tmp"

  if has_cmd systemctl; then
    systemctl daemon-reload >/dev/null 2>&1 || true
  fi

  print_ok "更新完成。"
  pause
}

render_header() {
  load_config

  printf "=================================
"
  printf "%s%s%s
" "$BOLD" "$APP_NAME" "$RESET"
  printf "=================================

"

  printf "当前隧道状态：%s

" "$(get_tunnel_status)"
  printf "当前出口模式：%s

" "$(exit_mode_label)"
  printf "当前出口 IPv6：%s

" "$(get_exit_ipv6)"
  printf "当前 MTU：%s

" "$(current_mtu)"
  printf "IPv6 优先级：%s

" "$(priority_label)"
  printf "禁止外部 Ping：%s

" "$(enabled_label "$BLOCK_PING")"
  printf "开机自启：%s

" "$(autostart_status)"
}

main_menu() {
  while true; do
    clear_screen
    render_header

    printf "1. 创建 HE 隧道
"
    printf "2. 删除 HE 隧道
"
    printf "3. 修改 HE 隧道
"
    printf "4. 查看隧道状态 / 当前配置
"
    printf "5. 查看出口 IPv6
"
    printf "6. 测试连通性
"
    printf "7. DNS 设置
"
    printf "8. MTU 设置
"
    printf "9. IPv6 防火墙
"
    printf "10. 开机自启管理
"
    printf "11. /48 IPv6 生成器
"
    printf "12. IPv6 优先级切换
"
    printf "13. 更新脚本
"
    printf "14. 退出

"
    printf "请选择："

    local choice=""
    IFS= read -r choice || choice=""

    case "$choice" in
      1) create_tunnel_interactive ;;
      2) delete_tunnel_interactive ;;
      3) modify_tunnel_interactive ;;
      4) show_status_and_config ;;
      5) show_exit_ipv6 ;;
      6) test_connectivity ;;
      7) dns_menu ;;
      8) mtu_menu ;;
      9) firewall_menu ;;
      10) autostart_menu ;;
      11) ipv6_48_generator ;;
      12) ipv6_priority_menu ;;
      13) update_script ;;
      14)
        printf "Bye.
"
        exit 0
        ;;
      *)
        print_warn "无效选择。"
        pause
        ;;
    esac
  done
}

usage() {
  cat <<EOF
$APP_NAME $VERSION

Usage:
  he                 进入交互式管理面板
  he --apply         根据 $CONFIG_FILE 创建/重建隧道
  he --down          删除当前隧道接口
  he --restart       重建隧道
  he --status        显示状态与配置
  he --update        更新脚本
  he --version       显示版本
  he --help          显示帮助
EOF
}

case "${1:-}" in
  --apply|start)
    apply_tunnel
    ;;
  --down|stop)
    down_tunnel
    ;;
  --restart|restart)
    down_tunnel
    apply_tunnel
    ;;
  --status|status)
    load_config
    printf "当前隧道状态：%s
" "$(get_tunnel_status)"
    printf "当前出口模式：%s
" "$(exit_mode_label)"
    printf "当前出口 IPv6：%s
" "$(get_exit_ipv6)"
    printf "curl 检测出口：%s
" "$(curl_exit_ipv6)"
    printf "当前 MTU：%s
" "$(current_mtu)"
    printf "IPv6 优先级：%s
" "$(priority_label)"
    printf "禁止外部 Ping：%s
" "$(enabled_label "$BLOCK_PING")"
    printf "开机自启：%s

" "$(autostart_status)"
    print_config
    ;;

  --update|update)
    update_script
    ;;
  --version|-v)
    printf "%s\n" "$VERSION"
    ;;
  --help|-h)
    usage
    ;;
  "")
    main_menu
    ;;
  *)
    usage
    exit 1
    ;;
esac
