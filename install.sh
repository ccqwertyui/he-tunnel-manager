#!/usr/bin/env bash
# Installer for HE Tunnel Broker Manager

set -Eeuo pipefail

APP_NAME="he-tunnel-manager"
INSTALL_DIR="${INSTALL_DIR:-/opt/he-tunnel-manager}"
BIN_PATH="${BIN_PATH:-/usr/local/bin/he}"
CONFIG_DIR="${CONFIG_DIR:-/etc/he-tunnel}"
CONFIG_FILE="${CONFIG_FILE:-${CONFIG_DIR}/config.conf}"
MANAGER_FILE="${MANAGER_FILE:-${CONFIG_DIR}/manager.conf}"
SERVICE_NAME="${SERVICE_NAME:-he-tunnel.service}"

# Default GitHub repository for online installation and updates.
OWNER_REPO="${OWNER_REPO:-ccqwertyui/he-tunnel-manager}"
BRANCH="${BRANCH:-main}"
RAW_BASE="${RAW_BASE:-https://raw.githubusercontent.com/${OWNER_REPO}/${BRANCH}}"

has_cmd() { command -v "$1" >/dev/null 2>&1; }

print_ok() { printf "\033[32m%s\033[0m\n" "$*"; }
print_warn() { printf "\033[33m%s\033[0m\n" "$*"; }
print_err() { printf "\033[31m%s\033[0m\n" "$*" >&2; }

require_root() {
  if [[ "${EUID:-$(id -u)}" -ne 0 ]]; then
    print_err "请使用 root 用户运行安装脚本。"
    exit 1
  fi
}

detect_local_mode() {
  local script_dir

  script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd || true)"
  if [[ -n "$script_dir" && -f "$script_dir/he.sh" && -d "$script_dir/systemd" ]]; then
    printf "%s" "$script_dir"
  else
    printf ""
  fi
}

detect_owner_repo_from_git() {
  local script_dir="$1"
  local url=""

  if ! has_cmd git || [[ -z "$script_dir" ]]; then
    return 1
  fi

  url="$(git -C "$script_dir" config --get remote.origin.url 2>/dev/null || true)"
  if [[ "$url" =~ github.com[:/]([^/]+)/([^/.]+)(\.git)?$ ]]; then
    printf "%s/%s" "${BASH_REMATCH[1]}" "${BASH_REMATCH[2]}"
    return 0
  fi

  return 1
}

install_dependencies() {
  local missing=0

  for cmd in ip curl ping; do
    if ! has_cmd "$cmd"; then
      missing=1
    fi
  done

  if [[ "$missing" -eq 0 ]]; then
    return 0
  fi

  print_warn "检测到部分依赖缺失，正在尝试安装常用依赖..."

  if has_cmd apt-get; then
    export DEBIAN_FRONTEND=noninteractive
    apt-get update
    apt-get install -y iproute2 curl wget iputils-ping git iptables
  elif has_cmd dnf; then
    dnf install -y iproute curl wget iputils git iptables
  elif has_cmd yum; then
    yum install -y iproute curl wget iputils git iptables
  elif has_cmd pacman; then
    pacman -Sy --noconfirm iproute2 curl wget iputils git iptables
  elif has_cmd zypper; then
    zypper --non-interactive install iproute2 curl wget iputils git iptables
  elif has_cmd apk; then
    apk add --no-cache iproute2 curl wget iputils git iptables bash
  else
    print_warn "未识别包管理器，请手动安装：bash iproute2 curl iputils-ping git iptables。"
  fi
}

fetch_file() {
  local url="$1"
  local output="$2"

  if has_cmd curl; then
    curl -fsSL "$url" -o "$output"
  elif has_cmd wget; then
    wget -qO "$output" "$url"
  else
    print_err "未检测到 curl 或 wget，无法下载文件。"
    return 1
  fi
}

install_from_dir() {
  local source_dir="$1"

  mkdir -p "$INSTALL_DIR" "$INSTALL_DIR/config" "$INSTALL_DIR/systemd" "$CONFIG_DIR"

  install -m 755 "$source_dir/he.sh" "$INSTALL_DIR/he.sh"
  install -m 755 "$source_dir/install.sh" "$INSTALL_DIR/install.sh"
  install -m 755 "$source_dir/uninstall.sh" "$INSTALL_DIR/uninstall.sh"

  if [[ -f "$source_dir/config/config.example.conf" ]]; then
    install -m 644 "$source_dir/config/config.example.conf" "$INSTALL_DIR/config/config.example.conf"
    if [[ ! -f "$CONFIG_FILE" ]]; then
      install -m 600 "$source_dir/config/config.example.conf" "$CONFIG_FILE"
    fi
  fi

  if [[ -f "$source_dir/systemd/he-tunnel.service" ]]; then
    install -m 644 "$source_dir/systemd/he-tunnel.service" "/etc/systemd/system/$SERVICE_NAME"
  fi

  ln -sf "$INSTALL_DIR/he.sh" "$BIN_PATH"

  cat > "$MANAGER_FILE" <<EOF
GITHUB_REPO="$OWNER_REPO"
GITHUB_BRANCH="$BRANCH"
INSTALL_DIR="$INSTALL_DIR"
RAW_BASE="https://raw.githubusercontent.com/${OWNER_REPO}/${BRANCH}"
EOF
  chmod 600 "$MANAGER_FILE"

  if has_cmd systemctl; then
    systemctl daemon-reload >/dev/null 2>&1 || true
  fi
}

install_from_github() {
  local tmp
  tmp="$(mktemp -d)"

  mkdir -p "$tmp/config" "$tmp/systemd"

  printf "正在从 GitHub 下载项目文件：%s\n" "$RAW_BASE"

  fetch_file "$RAW_BASE/he.sh" "$tmp/he.sh"
  fetch_file "$RAW_BASE/install.sh" "$tmp/install.sh"
  fetch_file "$RAW_BASE/uninstall.sh" "$tmp/uninstall.sh"
  fetch_file "$RAW_BASE/config/config.example.conf" "$tmp/config/config.example.conf"
  fetch_file "$RAW_BASE/systemd/he-tunnel.service" "$tmp/systemd/he-tunnel.service"

  install_from_dir "$tmp"
  rm -rf "$tmp"
}

main() {
  require_root

  local local_dir=""
  local detected_repo=""

  local_dir="$(detect_local_mode)"

  if [[ -n "$local_dir" ]]; then
    detected_repo="$(detect_owner_repo_from_git "$local_dir" || true)"
    if [[ -n "$detected_repo" && "$OWNER_REPO" == "ccqwertyui/he-tunnel-manager" ]]; then
      OWNER_REPO="$detected_repo"
      RAW_BASE="https://raw.githubusercontent.com/${OWNER_REPO}/${BRANCH}"
    fi
  fi

  install_dependencies

  if [[ -n "$local_dir" ]]; then
    install_from_dir "$local_dir"
  else
    install_from_github
  fi

  print_ok "安装完成。"
  printf "\n"
  printf "输入以下命令进入交互式管理面板：\n\n"
  printf "  he\n\n"
  printf "配置文件：%s\n" "$CONFIG_FILE"
  printf "安装目录：%s\n" "$INSTALL_DIR"
  printf "卸载命令：%s/uninstall.sh\n" "$INSTALL_DIR"
}

main "$@"
