#!/usr/bin/env bash
set -euo pipefail

log() { echo "[uninstall] $*"; }
warn() { echo "[uninstall][warn] $*" >&2; }
die() { echo "[uninstall][error] $*" >&2; exit 1; }

require_root() {
  [ "$(id -u)" -eq 0 ] || die "Run as root (use sudo)."
}

have() { command -v "$1" >/dev/null 2>&1; }

timestamp() { date "+%Y%m%d_%H%M%S"; }

backup_configs() {
  local base="/var/lib/netdata-cluster/backup"
  local ts; ts="$(timestamp)"
  local dst="${base}/${ts}"

  mkdir -p "${dst}"

  if [ -d /etc/netdata ]; then
    log "Backing up /etc/netdata to ${dst}/etc_netdata"
    mkdir -p "${dst}/etc_netdata"
    cp -a /etc/netdata/. "${dst}/etc_netdata/"
  fi

  if [ -f /etc/init.d/netdata ]; then
    log "Backing up /etc/init.d/netdata to ${dst}/init.d_netdata"
    mkdir -p "${dst}/init.d_netdata"
    cp -a /etc/init.d/netdata "${dst}/init.d_netdata/"
  fi

  {
    echo "BACKUP_TIMESTAMP=${ts}"
    echo "HOSTNAME=$(hostname 2>/dev/null || true)"
    echo "DATE=$(date -Iseconds 2>/dev/null || true)"
    echo "KERNEL=$(uname -r 2>/dev/null || true)"
  } > "${dst}/meta.env"

  log "Backup saved at ${dst}"
}

stop_disable_unmask_service() {
  if ! have systemctl; then
    warn "systemctl not found; skipping systemd operations."
    return 0
  fi

  # Stop if running (ignore errors)
  systemctl stop netdata.service 2>/dev/null || true

  # Disable if present (ignore errors)
  systemctl disable netdata.service 2>/dev/null || true

  # Unmask if masked (ignore errors)
  systemctl unmask netdata.service 2>/dev/null || true

  # Reload generator output after removing sysv init script
  systemctl daemon-reload 2>/dev/null || true
  systemctl reset-failed 2>/dev/null || true
}

remove_sysv_init_artifacts() {
  # If a sysv init script exists, systemd may generate a unit for it.
  if [ -f /etc/init.d/netdata ]; then
    log "Removing /etc/init.d/netdata (sysv init script)"
    rm -f /etc/init.d/netdata
  fi

  # Remove common sysv rc.d links if present
  rm -f /etc/rc0.d/*netdata* /etc/rc1.d/*netdata* /etc/rc2.d/*netdata* /etc/rc3.d/*netdata* \
        /etc/rc4.d/*netdata* /etc/rc5.d/*netdata* /etc/rc6.d/*netdata* 2>/dev/null || true
}

apt_purge_if_installed() {
  if ! have dpkg || ! have apt-get; then
    warn "dpkg/apt-get not found; skipping apt purge."
    return 0
  fi

  if dpkg -s netdata >/dev/null 2>&1; then
    log "Purging apt package: netdata"
    apt-get purge -y netdata || true
    apt-get autoremove -y || true
  else
    log "Apt package netdata not installed; skipping apt purge"
  fi
}

remove_leftover_files() {
  # Remove typical installed paths (safe even if absent)
  local paths=(
    "/usr/sbin/netdata"
    "/usr/bin/netdata"
    "/usr/lib/netdata"
    "/usr/share/netdata"
    "/var/lib/netdata"
    "/var/cache/netdata"
    "/var/log/netdata"
    "/run/netdata"
  )

  log "Removing leftover files/directories"
  rm -rf "${paths[@]}" 2>/dev/null || true
}

final_checks() {
  # systemd: unit should not exist after sysv/init artifacts are removed
  if have systemctl; then
    if systemctl status netdata.service >/dev/null 2>&1; then
      warn "netdata.service still visible (may be generated). Check /etc/init.d/netdata and rc*.d links."
    else
      log "netdata.service not found (expected)"
    fi
  fi

  # command resolution: this depends on caller shell cache; show file existence instead
  if [ -e /usr/sbin/netdata ] || [ -e /usr/bin/netdata ]; then
    warn "netdata binary still exists under /usr; removal incomplete."
  else
    log "netdata binary not present under /usr (expected)"
  fi

  if pgrep -a netdata >/dev/null 2>&1; then
    warn "netdata process still running; investigate manually."
  else
    log "no netdata process (expected)"
  fi

  log "Backups kept under /var/lib/netdata-cluster/backup"
  log "Note: if your interactive shell caches command paths, run: hash -r"
}

main() {
  require_root

  backup_configs

  stop_disable_unmask_service
  remove_sysv_init_artifacts

  apt_purge_if_installed
  remove_leftover_files

  # Reload systemd once more after removals
  if have systemctl; then
    systemctl daemon-reload 2>/dev/null || true
    systemctl reset-failed 2>/dev/null || true
  fi

  final_checks
  log "Done"
}

main "$@"
