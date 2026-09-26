# The machine-specific part of the flake example. The base (container profile
# + machine-configuration) comes from cm.nixosModules.default in ./flake.nix,
# because a flake never reads /etc/nixos/configuration.nix - compare
# ../nonflake/configuration.nix, which imports it instead.
{ pkgs, ... }:

{
  # Proof the example is active: `command -v cowsay` in the guest.
  environment.systemPackages = with pkgs; [ cowsay ];
}
