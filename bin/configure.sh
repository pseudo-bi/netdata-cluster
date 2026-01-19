#!/usr/bin/env bash
set -euo pipefail

log() { echo "[configure] $*"; }
die() { echo "[configure][error] $*" >&2; exit 1; }

usage() {
  cat <<'EOF'
Usage:
  sudo bin/configure.sh --role head  [--port <PORT>] [--api-key <KEY>]
  sudo bin/configure.sh --role child --head-ip <IP> [--port <PORT>] [--api-key <KEY>]

Notes:
  - Use the same --api-key on head and children.
  - If --api-key is omitted, a key is generated locally on that machine.

Examples:
  sudo bin/configure.sh --role head
  sudo bin/configure.sh --role child --head-ip 10.1.2.3

  sudo bin/configure.sh --role head  --api-key "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"
  sudo bin/configure.sh --role child --head-ip 10.1.2.3 --api-key "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"
EOF
}

require_root() {
  [ "$(id -u)" -eq 0 ] || die "Run as root (use sudo)."
}

have() { command -v "$1" >/dev/null 2>&1; }

timestamp() { date "+%Y%m%d_%H%M%S"; }

ensure_netdata() {
  have netdata || die "netdata is not installed. Run: sudo bin/install.sh"
  systemctl list-unit-files | grep -q '^netdata\.service' || die "netdata.service not found."
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
}

gen_key() {
  if have uuidgen; then
    uuidgen | tr '[:upper:]' '[:lower:]'
    return 0
  fi
  if [ -r /proc/sys/kernel/random/uuid ]; then
    cat /proc/sys/kernel/random/uuid
    return 0
  fi
  python3 - <<'PY'
import uuid
print(str(uuid.uuid4()))
PY
}

write_head_stream_conf() {
  local key="$1"
  mkdir -p /etc/netdata
  cat > /etc/netdata/stream.conf <<EOF
[receiver]
  enabled = yes
  api key = ${key}
EOF
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
}

restart_netdata() {
  log "Restarting netdata"
  systemctl restart netdata
  systemctl is-active --quiet netdata || die "netdata service is not active after restart."
}

main() {
  require_root
  ensure_netdata

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
  [ "$role" = "head" ] || [ "$role" = "child" ] || die "--role must be head or child."

  if [ "$role" = "child" ]; then
    [ -n "$head_ip" ] || { usage; die "--head-ip is required for child."; }
  fi

  if [ -z "$api_key" ]; then
    api_key="$(gen_key)"
    log "Generated API key: ${api_key}"
    log "Use the same key on head and children (pass via --api-key)."
  else
    log "Using provided API key."
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
