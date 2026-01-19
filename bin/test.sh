#!/usr/bin/env bash
set -euo pipefail

log() { echo "[test] $*"; }
die() { echo "[test][error] $*" >&2; exit 1; }

usage() {
  cat <<'EOF'
Usage:
  bin/test.sh --head-ip <IP> [--port <PORT>]

Examples:
  bin/test.sh --head-ip 10.1.2.3
  bin/test.sh --head-ip 10.1.2.3 --port 19999
EOF
}

have() { command -v "$1" >/dev/null 2>&1; }

tcp_check() {
  local ip="$1"
  local port="$2"

  if have nc; then
    nc -vz -w 2 "$ip" "$port" >/dev/null 2>&1
    return $?
  fi

  if have timeout; then
    timeout 2 bash -c "exec 3<>/dev/tcp/${ip}/${port}" >/dev/null 2>&1
    return $?
  fi

  return 2
}

api_check() {
  local ip="$1"
  local port="$2"
  local url="http://${ip}:${port}/api/v1/info"

  if have curl; then
    curl -fsS --max-time 3 "$url" >/dev/null
    return $?
  fi

  return 2
}

main() {
  local head_ip=""
  local port="19999"

  while [ "${#}" -gt 0 ]; do
    case "$1" in
      --head-ip) head_ip="${2:-}"; shift 2 ;;
      --port) port="${2:-}"; shift 2 ;;
      -h|--help) usage; exit 0 ;;
      *) die "Unknown argument: $1" ;;
    esac
  done

  [ -n "$head_ip" ] || { usage; die "--head-ip is required."; }

  log "HEAD_IP=${head_ip} PORT=${port}"

  log "TCP check"
  if tcp_check "$head_ip" "$port"; then
    log "TCP OK: ${head_ip}:${port}"
  else
    if [ "$?" -eq 2 ]; then
      die "Neither nc nor timeout is available. Install netcat-openbsd and coreutils."
    fi
    die "TCP NG: ${head_ip}:${port}"
  fi

  log "API check: /api/v1/info"
  if api_check "$head_ip" "$port"; then
    log "API OK: http://${head_ip}:${port}/api/v1/info"
  else
    if [ "$?" -eq 2 ]; then
      die "curl is not available. Install curl."
    fi
    die "API NG: http://${head_ip}:${port}/api/v1/info"
  fi

  log "Done"
}

main "$@"
