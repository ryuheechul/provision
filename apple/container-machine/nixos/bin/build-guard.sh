#!/usr/bin/env bash
# Refuse to overwrite an existing image archive without confirmation.
# Set FORCE_BUILD=1 for CI and other non-interactive callers.
set -euo pipefail

artifact="$1"

[ "${FORCE_BUILD:-0}" = 1 ] && exit 0
[ ! -s "$artifact" ] && exit 0

if [ ! -t 0 ]; then
  echo "image already exists: $artifact" >&2
  echo "rerun with FORCE_BUILD=1 to rebuild non-interactively" >&2
  exit 2
fi

read -r -p "Image already exists at $artifact. Build again? [y/N] " answer
case "$answer" in
  y|Y|yes|YES) ;;
  *)
    echo "Build cancelled."
    exit 1
    ;;
esac
