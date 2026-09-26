#!/usr/bin/env bash
# shellcheck disable=SC2154  # $out comes from the Nix runCommand env
# Materialize the Dockerfile build context alternative (`container build .`).
# Driven by image/default.nix (oci.nix) via the environment:
#   ROOTFS_TAR   path to the bare rootfs .tar.xz
#   DOCKERFILE   store path of the Dockerfile
#   $out          destination context dir (set by runCommand)
set -euo pipefail

mkdir -p "$out"
cp "$ROOTFS_TAR" "$out/rootfs.tar.xz"
cp "$DOCKERFILE" "$out/Dockerfile"
