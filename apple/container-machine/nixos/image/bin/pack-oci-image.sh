#!/usr/bin/env bash
# shellcheck disable=SC2154  # $out comes from the Nix runCommand env
# Assemble the minimal single-layer OCI image archive `container image load` eats.
# JSON structure comes from Nix templates (builtins.toJSON); this script only
# computes digests/sizes at build time and seds them into the @TOKEN@ placeholders.
# Driven by image/default.nix (oci.nix) via the environment:
#   ROOTFS_TREE            path to the unpacked+grafted rootfs tree
#   TAR_FLAGS              shared reproducible-tar flag list
#   OCI_CONFIG_TEMPLATE    store path of the config.json template
#   OCI_MANIFEST_TEMPLATE  store path of the manifest.json template
#   OCI_INDEX_TEMPLATE     store path of the index.json template
#   OCI_LAYOUT             store path of the oci-layout file
#   $out                    destination OCI archive tar (set by runCommand)
set -euo pipefail

mkdir -p image/blobs/sha256 work

# TAR_FLAGS is a space-separated flag list from Nix (no embedded spaces).
# shellcheck disable=SC2086
tar $TAR_FLAGS \
  -C "$ROOTFS_TREE" \
  -cf work/layer.tar \
  .

diff_id="$(sha256sum work/layer.tar | cut -d ' ' -f 1)"
gzip -n -c work/layer.tar >work/layer.tar.gz
layer_digest="$(sha256sum work/layer.tar.gz | cut -d ' ' -f 1)"
layer_size="$(stat -c %s work/layer.tar.gz)"
cp work/layer.tar.gz "image/blobs/sha256/$layer_digest"

sed \
  -e "s|@DIFF_ID@|$diff_id|g" \
  "$OCI_CONFIG_TEMPLATE" >work/config.json
config_digest="$(sha256sum work/config.json | cut -d ' ' -f 1)"
config_size="$(stat -c %s work/config.json)"
cp work/config.json "image/blobs/sha256/$config_digest"

# Size placeholders are JSON strings in the template; drop their quotes so
# the final document carries numbers, as the OCI spec requires.
sed \
  -e "s|@CONFIG_DIGEST@|$config_digest|g" \
  -e "s|@LAYER_DIGEST@|$layer_digest|g" \
  -e "s|\"@CONFIG_SIZE@\"|$config_size|g" \
  -e "s|\"@LAYER_SIZE@\"|$layer_size|g" \
  "$OCI_MANIFEST_TEMPLATE" >work/manifest.json
manifest_digest="$(sha256sum work/manifest.json | cut -d ' ' -f 1)"
manifest_size="$(stat -c %s work/manifest.json)"
cp work/manifest.json "image/blobs/sha256/$manifest_digest"

sed \
  -e "s|@MANIFEST_DIGEST@|$manifest_digest|g" \
  -e "s|\"@MANIFEST_SIZE@\"|$manifest_size|g" \
  "$OCI_INDEX_TEMPLATE" >image/index.json
cp "$OCI_LAYOUT" image/oci-layout

# shellcheck disable=SC2086
tar $TAR_FLAGS \
  -C image \
  -cf "$out" \
  .
