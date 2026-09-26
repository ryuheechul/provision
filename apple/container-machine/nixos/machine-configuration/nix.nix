# Feature defaults for a guest that still supports
# `nixos-rebuild switch` out of the box.
#
# NIX_PATH / channel are NOT set literally here: `nix.channel.enable` defaults
# to true and upstream's default `nix.nixPath` (nix-channel.nix) already carries
# the channel + nixos-config entries (sessionVariables -> /etc/set-environment).
# `make switch` sources that file instead of hardcoding NIX_PATH.
# The one exception is a flake-built system - see setNixPath below.
# trusted-users defaults to [ "root" ] upstream as well.
{ lib, ... }:

{
  # Upstream NixOS does not put these in nix.conf by default.
  nix.settings.experimental-features = lib.mkDefault [ "nix-command" "flakes" ];

  # Built from a flake, nixpkgs.flake.source is set and upstream then swaps
  # NIX_PATH for `nixpkgs=flake:nixpkgs` while deliberately dropping
  # `nixos-config` (nixos/modules/misc/nixpkgs-flake.nix). Channel-mode
  # `nixos-rebuild switch` then fails with "file 'nixos-config' was not found",
  # so `make switch` / `make switch-nonflake` break after `make switch-flake`.
  # This machine switches via the channel + /etc/nixos/configuration.nix (see
  # README), so keep nix-channel.nix's default in every path. The flake
  # registry pin (nixpkgs.flake.setFlakeRegistry) stays on, which is what keeps
  # `nix run nixpkgs#...` pinned to the system's own nixpkgs.
  nixpkgs.flake.setNixPath = false;
}
