# Minimal non-flake configuration for this machine. Switch to it with
# `make switch-nonflake`.
#
# Same shape as a dotfiles configuration.nix (ryuheechul/dotfiles): import the
# machine's own /etc/nixos/configuration.nix as the base - the generated entry
# that brings in the container profile plus the live overlay (or the baked
# copy) - then add what you want on top of it.
{ pkgs, ... }:

{
  imports = [
    /etc/nixos/configuration.nix
  ];

  # Proof the example is active: `command -v hello` in the guest.
  environment.systemPackages = with pkgs; [ hello ];
}
