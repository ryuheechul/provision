#!/usr/bin/env bash
# Build the NixOS container-machine OCI archive inside an Apple `container`
# sandbox running the official `nixos/nix` image - no Lima VM needed.
#
# The image is aarch64-linux, and a macOS host cannot build it natively, so
# this does the build inside a linux/arm64 container that ships a full nix.
# The final OCI archive is copied back onto the host's `build/` dir (the
# container's /nix/store is ephemeral and not readable from macOS).
#
# Two network entrances:
#   default   - use the `container` default network (the common case; stable
#               NAT, works out of the box).
#   fresh     - create a dedicated network and build on it. Use this when the
#               default network has no outbound connectivity (observed when a
#               VPN/Tailscale default-route conflict blackholes the default
#               vmnet NAT; a freshly created network forwards correctly).
#
# Env:
#   CONTAINER_BUILD_NETWORK  default|fresh   (default "default")
#   CONTAINER_BUILD_IMAGE    nixos/nix       (default "nixos/nix")
#   CONTAINER_BUILD_MEMORY   builder RAM     (default "6G" - the NixOS tarball
#                             assembly OOMs at the default container limit)
#   CONTAINER_BUILD_CPUS     builder CPUs    (default "4")
#
# Usage: bin/build-on-container.sh [nix-build-extra-args...]
set -euo pipefail

# cd into this script's own directory so every relative path below is true
# from the file's location, no matter where the script was called from.
script_dir="$(cd "$(dirname "$0")" && pwd -P)"
cd "$script_dir"

./build-guard.sh ../build/nixos-machine-image.tar

command -v container >/dev/null || { echo "Apple 'container' CLI not found" >&2; exit 1; }

network_mode="${CONTAINER_BUILD_NETWORK:-default}"
image="${CONTAINER_BUILD_IMAGE:-nixos/nix}"
mem="${CONTAINER_BUILD_MEMORY:-6G}"
cpus="${CONTAINER_BUILD_CPUS:-4}"
net_name="container-nix-builder"

if [ "$network_mode" = "fresh" ]; then
  # create the builder network if it isn't there yet
  if ! container network list 2>/dev/null | awk '{print $1}' | grep -qx "$net_name"; then
    container network create "$net_name" >/dev/null
  fi
  net=("--network" "$net_name")
else
  net=("--network" "default")
fi

# make sure the image is present (pull is a no-op if already loaded)
container image pull "$image" >/dev/null

# --volume the project dir (NOT /nix - overlaying /nix hides the image's own
# store/binaries). The container's /nix/store is a writable overlay holding the
# build; the final tar is copied to the bind-mounted project so macOS can read
# it. The container gets the project root, one level above this script.
project="$(dirname "$script_dir")"

# --rm makes `container run` discard the container (and its on-disk storage)
# once the build stops, so repeated builds don't leave stopped containers
# behind or leak disk.
container run "${net[@]}" \
  --rm \
  --volume "$project:/workspace" \
  --memory "$mem" \
  --cpus "$cpus" \
  -e 'NIX_CONFIG=experimental-features = nix-command flakes' \
  "$image" \
  sh -c '
    set -e
    cd /workspace
    export NIX_PATH="nixpkgs=channel:nixpkgs"
    nix-build image -A image -o build/result --option sandbox false "$@"
    # build/result is a symlink into the ephemeral /nix/store; copy a real
    # archive into the bind-mounted project (artifact is 0444, drop any old one)
    rm -f build/nixos-machine-image.tar
    cp -L build/result build/nixos-machine-image.tar
  ' _ "$@"

echo
echo "OCI archive built at $project/build/nixos-machine-image.tar"
echo "Next, from macOS:"
echo "  bin/launch.sh    # loads the image and creates the machine"
