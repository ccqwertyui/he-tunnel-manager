#!/usr/bin/env bash
# Uninstaller for HE Tunnel Broker Manager

set -Eeuo pipefail

INSTALL_DIR="${INSTALL_DIR:-/opt/he-tunnel-manager}"
BIN_PATH="${BIN_PATH:-/usr/local/bin/he}"
CONFIG_DIR="${CONFIG_DIR:-/etc/he-tunnel}"
SERVICE_NAME="${SERVICE_NAME:-he-tunnel.service}"

print_ok() { printf "\033[32m%s\033[0m\n" "$*"; }
print_warn() { printf "\033[33m%s\033[0m\n" "$*"; }
print_err() { printf "\033[31m%s\033[0m\n" "$*" >&2; }
has_cmd() { command -v "$1" >/dev/null 2>&1; }

require_root() {
  if [[ "${EUID:-$(id -u)}" -ne 0 ]]; then
    print_err "请使用 root 用户运行卸载脚本。"
    exit 1
  fi
}

confirm() {
  local prompt="$1"
  local default="${2:-N}"
  local answer=""

  printf "%s\nY/N\n> " "$prompt"
  IFS= read -r answer || answer=""
  answer="${answer:-$default}"

  case "$answer" in
    y|Y|yes|YES|Yes) return 0 ;;
    *) return 1 ;;
  esac
}

main() {
  require_root

  if has_cmd systemctl; then
    systemctl disable --now "$SERVICE_NAME" >/dev/null 2>&1 || true
    systemctl daemon-reload >/dev/null 2>&1 || true
  fi

  if [[ -x "$BIN_PATH" ]]; then
    "$BIN_PATH" --down >/dev/null 2>&1 || true
  elif [[ -x "$INSTALL_DIR/he.sh" ]]; then
    "$INSTALL_DIR/he.sh" --down >/dev/null 2>&1 || true
  fi

  rm -f "/etc/systemd/system/$SERVICE_NAME"
  rm -f "$BIN_PATH"
  rm -rf "$INSTALL_DIR"

  if has_cmd systemctl; then
    systemctl daemon-reload >/dev/null 2>&1 || true
  fi

  if [[ "${1:-}" == "--purge" ]]; then
    rm -rf "$CONFIG_DIR"
    print_ok "已卸载 HE Tunnel Broker Manager，并删除配置目录。"
    exit 0
  fi

  if [[ -d "$CONFIG_DIR" ]]; then
    if confirm "是否删除配置目录 $CONFIG_DIR？" "N"; then
      rm -rf "$CONFIG_DIR"
      print_ok "配置目录已删除。"
    else
      print_warn "配置目录已保留：$CONFIG_DIR"
    fi
  fi

  print_ok "卸载完成。"
}

main "$@"
