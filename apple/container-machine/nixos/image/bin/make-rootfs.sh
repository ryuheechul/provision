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
# Also writes $out/etc/nixos/image-gcroots.manifest: every store path the
# rootfs references, for the GC-roots activation (image-gcroots.nix).
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

# GC roots manifest (see machine-configuration/image-gcroots.nix): nix only
# protects store paths reachable from roots (profiles, gcroots), and it
# cannot see that rootfs files reference anything - /init -> image system,
# the /bin shims -> image coreutils/gnugrep/getent, and
# every other store path the grafts above or the tarball wrote outside
# /nix. A guest-run nix-collect-garbage would keep the files but collect
# their targets: boot then dies at exec /sbin/init (127) with no way back
# into the machine to repair it. Manifest every store reference outside
# /nix (references inside the store are tracked in nix's DB and become
# protected transitively once the rooted ones are); activation turns the
# manifest into real GC roots before any user GC can run.
manifest="$out/etc/nixos/image-gcroots.manifest"
{
  # Symlink targets: first component after /nix/store IS the store path
  # (the rest of the target may be a subpath inside it).
  while IFS= read -r -d '' link; do
    target=$(readlink "$link")
    case "$target" in
      /nix/store/*)
        rest="${target#/nix/store/}"
        printf '/nix/store/%s\n' "${rest%%/*}"
        ;;
    esac
  done < <(find "$out" -path "$out/nix" -prune -o -type l -print0)
  # Textual references (including ELF binaries): the regex stops at the
  # first component, which is exactly the store path. Over-collection is
  # fine - the activation side skips paths that do not exist. The one
  # exception is nix-path-registration: it is a nix-store --dump-db dump
  # of the build machine's whole database (2517 records in the current
  # tarball), not a rootfs reference, and scanning it pinned the build
  # toolchain - gcc, binutils, stdenv and hooks, ~0.31 GiB - that
  # nothing in the image references at runtime. Everything that must
  # stay rooted is a genuine hit elsewhere: the image toplevel behind
  # /init, the /bin shim symlink targets above, the passwd shell.
  find "$out" -path "$out/nix" -prune -o -type f \
    ! -name nix-path-registration -print0 | \
    xargs -0 -r grep -a -h -o -E '/nix/store/[A-Za-z0-9+._?-]+' || true
} | sort -u > "$manifest"
