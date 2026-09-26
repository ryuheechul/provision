#!/usr/bin/env bash
# shellcheck disable=SC2154  # $out comes from the Nix runCommand env
# Pack the rootfs tree into a bare rootfs .tar.xz (for `container build`).
# Driven by image/default.nix (rootfs.nix) via the environment:
#   ROOTFS_TREE  path to the unpacked+grafted rootfs tree
#   TAR_FLAGS    shared reproducible-tar flag list (space-separated, no spaces inside)
#   $out          destination archive (set by runCommand)
set -euo pipefail

# TAR_FLAGS is a space-separated flag list from Nix (no embedded spaces).
# shellcheck disable=SC2086
tar $TAR_FLAGS \
  -C "$ROOTFS_TREE" \
  -cJf "$out" \
  .
