#!/usr/bin/env bash
set -euo pipefail

log() { echo "[configure] $*"; }
die() { echo "[configure][error] $*" >&2; exit 1; }

usage() {
  cat <<'EOF'
Usage:
  sudo bin/configure.sh --role head  --api-key <KEY> [--port <PORT>]
  sudo bin/configure.sh --role child --head-ip <IP> --api-key <KEY> [--port <PORT>]

Notes:
  - Use the same API key on head and all children.
  - This script writes /etc/netdata/stream.conf and restarts netdata.
  - It does NOT modify hostname and does NOT touch /etc/hosts.

Examples:
  sudo bin/configure.sh --role head --api-key "a0856a66-7760-4633-99ce-d7005bcf3d96"
  sudo bin/configure.sh --role child --head-ip 10.1.2.3 --api-key "a0856a66-7760-4633-99ce-d7005bcf3d96"
EOF
}

require_root() {
  [ "$(id -u)" -eq 0 ] || die "Run as root (use sudo)."
}

have() { command -v "$1" >/dev/null 2>&1; }

timestamp() { date "+%Y%m%d_%H%M%S"; }

ensure_netdata_service() {
  have netdata || die "netdata command not found. Run: sudo bin/install.sh"
  systemctl cat netdata >/dev/null 2>&1 || die "netdata.service not found (systemd unit missing)."
}

backup_etc_netdata() {
  local base="/var/lib/netdata-cluster/backup"
  local ts; ts="$(timestamp)"
  local dst="${base}/${ts}/etc_netdata"

  mkdir -p "$dst"

  if [ -d /etc/netdata ]; then
    log "Backing up /etc/netdata to ${dst}"
    cp -a /etc/netdata/. "$dst/"
  fi

  mkdir -p "${base}/${ts}"
  {
    echo "BACKUP_TIMESTAMP=${ts}"
    echo "HOSTNAME=$(hostname 2>/dev/null || true)"
    echo "DATE=$(date -Iseconds 2>/dev/null || true)"
  } > "${base}/${ts}/meta.env"

  log "Backup saved at ${base}/${ts}"
}

write_head_stream_conf() {
  local key="$1"
  mkdir -p /etc/netdata

  cat > /etc/netdata/stream.conf <<EOF
[receiver]
  enabled = yes
  api key = ${key}
EOF

  log "Wrote /etc/netdata/stream.conf (receiver enabled)"
}

write_child_stream_conf() {
  local key="$1"
  local head_ip="$2"
  local port="$3"
  mkdir -p /etc/netdata

  cat > /etc/netdata/stream.conf <<EOF
[stream]
  enabled = yes
  destination = ${head_ip}:${port}
  api key = ${key}
EOF

  log "Wrote /etc/netdata/stream.conf (stream enabled)"
}

restart_netdata() {
  log "Restarting netdata"
  systemctl restart netdata
  systemctl is-active --quiet netdata || die "netdata is not active after restart."
  log "netdata is active"
}

main() {
  require_root
  ensure_netdata_service

  local role=""
  local head_ip=""
  local port="19999"
  local api_key=""

  while [ "${#}" -gt 0 ]; do
    case "$1" in
      --role) role="${2:-}"; shift 2 ;;
      --head-ip) head_ip="${2:-}"; shift 2 ;;
      --port) port="${2:-}"; shift 2 ;;
      --api-key) api_key="${2:-}"; shift 2 ;;
      -h|--help) usage; exit 0 ;;
      *) die "Unknown argument: $1" ;;
    esac
  done

  [ -n "$role" ] || { usage; die "--role is required."; }
  [ -n "$api_key" ] || { usage; die "--api-key is required."; }

  if [ "$role" != "head" ] && [ "$role" != "child" ]; then
    die "--role must be head or child."
  fi

  if [ "$role" = "child" ] && [ -z "$head_ip" ]; then
    usage
    die "--head-ip is required for child."
  fi

  backup_etc_netdata

  if [ "$role" = "head" ]; then
    log "Configuring as head (receiver)"
    write_head_stream_conf "$api_key"
  else
    log "Configuring as child (stream)"
    write_child_stream_conf "$api_key" "$head_ip" "$port"
  fi

  restart_netdata
  log "Done"
}

main "$@"
