#!/usr/bin/env bash
# Load the NixOS OCI archive built by image/ into `container` and create a
# container machine from it. This is the macOS-side of the flow.
#
# The machine is STATEFUL: /home/<user> and anything switched in persist on its
# disk (rootfs.ext4). By default this script never touches an existing machine
# (create-if-missing only). Only --recreate deletes, after an interactive
# confirmation that the machine holds persisted state.
#
# Usage:
#   bin/launch.sh                        # load image + create machine (create-if-missing)
#   bin/launch.sh --recreate             # destroy existing machine + recreate (prompts first)
#   bin/launch.sh [path/to/oci-archive]  # custom archive path
#   bin/launch.sh --recreate [path/to/oci-archive]
#
# Runs from any working directory; the default archive is this project's own
# build/. An explicit relative path is resolved against your cwd.
#
# Env:  MACHINE_NAME (default "nixos")
#       IMAGE (default "local/nixos-cm:latest"; matches image/default.nix)
set -euo pipefail

caller_pwd="$(pwd -P)"
script_dir="$(cd "$(dirname "$0")" && pwd -P)"
project="$(dirname "$script_dir")"
cd "$script_dir"

command -v container >/dev/null || { echo "Apple 'container' CLI not found" >&2; exit 1; }

recreate=0
archive=""
for arg in "$@"; do
  case "$arg" in
    --recreate) recreate=1 ;;
    *) archive="$arg" ;;
  esac
done
name="${MACHINE_NAME:-nixos}"
image="${IMAGE:-local/nixos-cm:latest}"

# no argument -> this project's build/; a relative argument -> the caller's cwd
case "${archive:-}" in
  "") archive="$project/build/nixos-machine-image.tar" ;;
  /*) ;;
  *) archive="$caller_pwd/$archive" ;;
esac

# macOS ships no `realpath`; expand the archive path via the shell. Tolerate a
# missing dir (no build yet) so the error below reads clearly instead of a
# mangled path - a bare `cd` failure would otherwise leave a stray leading `/`.
adir="$(dirname "$archive")"
if [ -d "$adir" ]; then
  archive="$(cd "$adir" && pwd -P)/$(basename "$archive")"
fi
[ -f "$archive" ] || { echo "archive not found: $archive (run bin/build-on-container.sh first)" >&2; exit 2; }

container image load --input "$archive"

if container machine list 2>/dev/null | grep -q "^$name[[:space:]]"; then
  if [ "$recreate" -eq 1 ]; then
    # confirmation gate: the machine holds persisted state that will be lost
    read -p "Delete existing machine '$name'? This erases its persisted state (e.g. /home). Type yes to confirm: " ans
    if [ "$ans" = "yes" ]; then
      container machine delete "$name"
      echo "machine '$name' deleted"
    else
      echo "Aborted. machine '$name' was left untouched." >&2
      exit 1
    fi
  else
    echo "machine '$name' already exists; leaving it as-is (use bin/launch.sh --recreate to destroy and recreate)"
    echo
    echo "Shell in:"
    echo "  container machine run -n $name"
    echo "  (root work: container machine run -n $name --root '...')"
    echo "See README.md in the project root for the user model, disk footprint, and clean-up."
    exit 0
  fi
fi

# Apple provisions the user on first boot (not baked into the image); PATH
# and sudo shims are. --home-mount rw lets the guest read this repo for
# `make sync-config` / `make switch`.
container machine create "$image" --name "$name" --cpus 4 --memory 8G --home-mount rw

# `container machine create` returns before the guest can run commands - they
# fail with "Operation not supported by device" until systemd is up - so wait
# for it. Otherwise the hints below (and `make status` right after
# `make recreate`) fail for the first few seconds.
echo "waiting for '$name' to finish booting..."
ready=""
for _ in $(seq 1 30); do
  state="$(container machine run -n "$name" --root 'systemctl is-system-running' 2>/dev/null || true)"
  case "$state" in
    running|degraded) ready=1; break ;;
  esac
  sleep 1
done
if [ -z "$ready" ]; then
  # Unknown boot state: report it plainly rather than promising a shell-in that
  # would fail, and leave the next step to the user. Exit 0 because the machine
  # does exist - a failure here would make `make recreate` look broken.
  echo
  echo "machine '$name' created, but its boot state is still unknown after 30s."
  echo "Check with: make status"
  exit 0
fi

echo
echo "machine '$name' created; PATH/sudo shims are in the image, user comes from Apple provisioning."
echo "Shell in:"
echo "  container machine run -n $name"
echo "  (root work: container machine run -n $name --root '...')"
echo "See README.md in the project root for the user model, disk footprint, and clean-up."
