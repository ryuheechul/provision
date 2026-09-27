#!/usr/bin/env bash
# Build the NixOS container-machine OCI archive.
#
# Must run on a Linux builder (the image is aarch64-linux; a macOS host cannot
# build it natively). Good options:
#   - your lima VM,
#   - any aarch64 Linux box with nix (an ARM VM, CI runner, ...).
#
# NIX_PATH must point at a nixpkgs (defaults to channel:nixos-26.05 here -
# the release branch the guest runtime channel also uses. Deliberately not
# channel:nixpkgs: that alias resolved differently per machine - stale
# fallback in the builder container, trunk on a host - so CI and local
# builds could silently disagree).
#
# Usage: bin/build.sh [nix-build-extra-args...]
set -euo pipefail

# cd into this script's own directory so every relative path below is true
# from the file's location, no matter where the script was called from.
script_dir="$(cd "$(dirname "$0")" && pwd -P)"
cd "$script_dir"

./build-guard.sh ../build/nixos-machine-image.tar

export NIX_PATH="${NIX_PATH:-nixpkgs=channel:nixos-26.05}"

nix-build ../image -A image -o ../build/result "$@"

# ../build/result is a symlink into the builder's /nix/store, which macOS can't
# read through a lima mount; copy a real archive next to it (the store
# artifact is 0444, so drop any previous copy first)
rm -f ../build/nixos-machine-image.tar
cp -L ../build/result ../build/nixos-machine-image.tar

echo
echo "OCI archive built at $(realpath ../build/nixos-machine-image.tar)"
echo "Next, from macOS:"
echo "  bin/launch.sh    # loads the image and creates the machine"
