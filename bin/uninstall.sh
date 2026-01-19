#!/usr/bin/env bash
set -euo pipefail

log() { echo "[uninstall] $*"; }
die() { echo "[uninstall][error] $*" >&2; exit 1; }

require_root() {
  [ "$(id -u)" -eq 0 ] || die "Run as root (use sudo)."
}

timestamp() {
  date "+%Y%m%d_%H%M%S"
}

backup_configs() {
  local base="/var/lib/netdata-cluster/backup"
  local ts="$(timestamp)"
  local dst="${base}/${ts}"

  mkdir -p "${dst}"

  if [ -d /etc/netdata ]; then
    log "Backing up /etc/netdata to ${dst}/etc_netdata"
    mkdir -p "${dst}/etc_netdata"
    cp -a /etc/netdata/. "${dst}/etc_netdata/"
  fi

  {
    echo "BACKUP_TIMESTAMP=${ts}"
    echo "HOSTNAME=$(hostname 2>/dev/null || true)"
    echo "DATE=$(date -Iseconds 2>/dev/null || true)"
  } > "${dst}/meta.env"

  log "Backup saved at ${dst}"
}

main() {
  require_root
  backup_configs

  log "Stopping service"
  systemctl stop netdata 2>/dev/null || true
  systemctl disable netdata 2>/dev/null || true

  log "Purging netdata"
  apt-get purge -y netdata || true
  apt-get autoremove -y || true

  log "Removing residual directories"
  rm -rf /var/lib/netdata /var/cache/netdata /var/log/netdata /usr/lib/netdata 2>/dev/null || true

  log "Done. Backups kept under /var/lib/netdata-cluster/backup"
}

main "$@"
