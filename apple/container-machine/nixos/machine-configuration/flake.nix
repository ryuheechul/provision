# Flake entry point for this container machine: exposes the machine's NixOS
# module set so a flake-based configuration can consume it.
#
# A flake never reads /etc/nixos/configuration.nix (the non-flake path does -
# see examples/nonflake), so this module carries the same base that the image
# build and the generated /etc/nixos/configuration.nix use.
#
# It lives inside machine-configuration/ on purpose: the directory itself is
# the flake root, so the copy the image grafts at
# /etc/nixos/machine-configuration.baked (a flake input with no network, no
# push) and the live overlay at /etc/nixos/machine-configuration are both
# consumable from inside the machine:
#   inputs.cm.url = "path:/etc/nixos/machine-configuration.baked";
# Outside this machine, consume it by URL:
#   inputs.cm.url = "github:ryuheechul/provision?dir=apple/container-machine/nixos/machine-configuration";
{
  description = "NixOS module for an Apple container container-machine";

  outputs = { self }: {
    nixosModules.default = { modulesPath, ... }: {
      imports = [
        # Tarball packaging + container markers, the same profile the image
        # build uses (image/default.nix). lxc-container.nix was considered and
        # rejected; see machine-configuration/default.nix for why.
        "${modulesPath}/virtualisation/docker-image.nix"
        # this directory - the machine-configuration module tree itself
        ./.
      ];
    };
  };
}
