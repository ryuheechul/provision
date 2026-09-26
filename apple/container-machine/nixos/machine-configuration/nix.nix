# Feature defaults for a bare (non-flake) guest that still supports
# `nixos-rebuild switch` out of the box.
#
# NIX_PATH / channel are NOT set here: `nix.channel.enable` defaults to true
# and upstream's default `nix.nixPath` already carries the channel +
# nixos-config entries (sessionVariables -> /etc/set-environment).
# `make switch` sources that file instead of hardcoding NIX_PATH.
# trusted-users defaults to [ "root" ] upstream as well.
{ lib, ... }:

{
  # Upstream NixOS does not put these in nix.conf by default.
  nix.settings.experimental-features = lib.mkDefault [ "nix-command" "flakes" ];
}
