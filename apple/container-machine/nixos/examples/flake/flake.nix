# Example flake configuration for this machine. Switch to it with
# `make switch-flake`.
{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";

    # This repository's flake as the image ships it: machine-configuration/
    # carries flake.nix, and the image grafts that directory at
    # /etc/nixos/machine-configuration.baked - a real directory, so no push
    # and no network (for `cm`). Image-frozen: it follows the image, not your
    # edits.
    cm.url = "path:/etc/nixos/machine-configuration.baked";
    # Want the live tree instead (what sync-config / make switch writes)?
    # Uncomment - it tracks your current machine-configuration:
    # cm.url = "path:/etc/nixos/machine-configuration";
    # Consuming it from outside this machine? Uncomment the GitHub URL:
    # cm.url = "github:ryuheechul/provision?dir=apple/container-machine/nixos/machine-configuration";
    # then run `nix flake lock` to pin the pushed commit.
  };

  outputs = { self, nixpkgs, cm }: {
    # The stable entry point: make switch-flake always passes #default, so the
    # rebuild never depends on the guest's current hostname. nixos-rebuild does
    # not single this one out on its own - with no #attr it looks up
    # nixosConfigurations.$(hostname) instead, which is why the Makefile never
    # omits the attr.
    nixosConfigurations.default = nixpkgs.lib.nixosSystem {
      system = "aarch64-linux";
      modules = [
        cm.nixosModules.default
        ./configuration.nix
      ];
    };
  };
}
