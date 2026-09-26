#!/usr/bin/env bash
# shellcheck disable=SC2154  # $out comes from the Nix runCommand env
# Unpack the NixOS system tarball and graft the container-machine boot bits.
# Driven by image/default.nix (rootfs.nix) via the environment:
#   NIXOS_SYSTEM_TARBALL  path to nixos-system-*.tar.xz
#   OS_RELEASE            store path of the os-release file
#   BIN_SH                store path of the /bin/sh shim
#   BIN_SHIMS             one "name=/nix/store/.../bin/foo" entry per line
#   SHELL_BOOTSTRAP       store path of the wait-for-/run/current-system shim
#   MACHINE_CONFIGURATION source tree for the baked configuration fallback
#   $out                   destination rootfs tree (set by runCommand)
set -euo pipefail

mkdir -p "$out"
tar -xJf "$NIXOS_SYSTEM_TARBALL" -C "$out"

chmod u+w "$out/etc"
cp "$OS_RELEASE" "$out/etc/os-release"

# Baked configuration fallback (see machine-configuration/default.nix): the
# guest uses this until sync-config introduces the live overlay at
# /etc/nixos/machine-configuration. Lives in the rootfs, not the store, so
# it survives GC and changes only when the image is rebuilt.
mkdir -p "$out/etc/nixos"
cp -r "$MACHINE_CONFIGURATION" "$out/etc/nixos/machine-configuration.baked"

mkdir -p "$out/bin" "$out/sbin"
chmod u+w "$out/bin" "$out/sbin"

# container-machine boots the image's init; NixOS system tarballs ship /init
ln -sfn /init "$out/sbin/init"
mkdir -p "$out/run"
ln -sfn / "$out/run/current-system"
install -m 0755 "$BIN_SH" "$out/bin/sh"

# Pre-activation shell for passwd entries (see machine-configuration/shell.nix).
# /run/current-system is not linkable yet when Apple's init execs the passwd
# shell; this shim waits for it and hands off.
install -m 0755 "$SHELL_BOOTSTRAP" "$out/bin/container-machine-shell"

while IFS= read -r entry; do
  [ -n "$entry" ] || continue
  name="${entry%%=*}"
  path="${entry#*=}"
  ln -sfn "$path" "$out/bin/$name"
done <<< "$BIN_SHIMS"
