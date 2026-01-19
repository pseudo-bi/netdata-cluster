#!/usr/bin/env bash
set -euo pipefail

# Generate a UUID-style API key for Netdata streaming.
# Output exactly one line.

if [ -r /proc/sys/kernel/random/uuid ]; then
  cat /proc/sys/kernel/random/uuid
  exit 0
fi

if command -v uuidgen >/dev/null 2>&1; then
  uuidgen | tr '[:upper:]' '[:lower:]'
  exit 0
fi

echo "ERROR: cannot generate UUID (no /proc/sys/kernel/random/uuid and no uuidgen)" >&2
exit 1
