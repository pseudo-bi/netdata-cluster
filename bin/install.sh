#!/usr/bin/env bash
set -euo pipefail

log() { echo "[install] $*"; }
die() { echo "[install][error] $*" >&2; exit 1; }

require_root() {
  [ "$(id -u)" -eq 0 ] || die "Run as root (use sudo)."
}

check_ubuntu() {
  [ -r /etc/os-release ] || die "/etc/os-release not found."
  . /etc/os-release
  [ "${ID}" = "ubuntu" ] || die "Ubuntu is required (ID=${ID})."
}

main() {
  require_root
  check_ubuntu

  log "Updating apt index"
  apt-get update -y

  log "Installing netdata"
  apt-get install -y netdata

  log "Enabling and starting service"
  systemctl enable --now netdata

  systemctl is-active --quiet netdata || die "netdata service is not active."

  log "Installed: $(netdata -v 2>/dev/null || echo unknown)"
  log "Done. Next: bin/test.sh and bin/configure.sh"
}

main "$@"
