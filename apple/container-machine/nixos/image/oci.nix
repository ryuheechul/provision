# OCI image archive + Dockerfile build-context derivations.
# Shell logic lives in bin/; this module only wires Nix inputs.
{ pkgs, rootfsTree, rootfs, common }:

{
  # minimal single-layer OCI image archive: what `container image load` eats.
  image = pkgs.runCommand "nixos-machine-image.tar" {
    nativeBuildInputs = [ pkgs.coreutils pkgs.gnutar pkgs.gzip pkgs.gnused ];
    ROOTFS_TREE = "${rootfsTree}";
    TAR_FLAGS = common.tarFlags;
    OCI_CONFIG_TEMPLATE = "${common.ociConfigTemplate}";
    OCI_MANIFEST_TEMPLATE = "${common.ociManifestTemplate}";
    OCI_INDEX_TEMPLATE = "${common.ociIndexTemplate}";
    OCI_LAYOUT = "${common.ociLayout}";
  } (builtins.readFile ./bin/pack-oci-image.sh);

  # Manual fallback (less tested than the load path). Prefer `make build-context`:
  #   make build-context
  #   # or: nix-build image -A buildContext -o build/build-context
  #   cp -L build/build-context /tmp/ctx && cd /tmp/ctx
  #   container build -t local/nixos-cm .
  buildContext = pkgs.runCommand "nixos-machine-container-build-context" {
    ROOTFS_TAR = "${rootfs}";
    DOCKERFILE = "${common.dockerfile}";
  } (builtins.readFile ./bin/make-build-context.sh);
}
