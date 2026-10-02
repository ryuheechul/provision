# Persistent NixOS machine configuration for an Apple `container` container-machine.
#
# Analogous to hardware-configuration.nix: machine-specific module tree that
# /etc/nixos/configuration.nix imports (as the machine-configuration directory
# - not hardware-only: runtime shims, users, and nix settings too).
#
# Used both while constructing the image and as /etc/nixos/machine-configuration/
# on the guest, so runtime shims survive nixos-rebuild switch.
{ lib, pkgs, ... }:

{
  imports = [
    ./networking.nix
    ./shell.nix
    ./sudo.nix
    ./users.nix
    ./runtime.nix
    ./nix.nix
  ];

  system.stateVersion = lib.mkDefault "26.05";
  networking.hostName = lib.mkDefault "nixos-cm";

  # Explicit pins so the image keeps these tools even if the container
  # profile drops them from the default set.
  environment.systemPackages = with pkgs; [
    bashInteractive
    cacert
    git
    curl
    nix
  ];

  # configuration.nix is the only self-staged entry. It picks between the two
  # machine-configuration paths - the single place precedence is decided:
  #   /etc/nixos/machine-configuration        live overlay: created by
  #     sync-config (make switch), moved aside to machine-configuration.bak by
  #     switch-nonflake-baked (restore-config moves it back); present -> wins.
  #   /etc/nixos/machine-configuration.baked  this tree as grafted into the
  #     image (image/bin/make-rootfs.sh); used while no overlay exists
  #     (fresh machine, or after the overlay is removed).
  # The overlay is deliberately NOT an environment.etc entry: two writers for
  # one path is what made setup-etc warn on every switch, and activation must
  # never delete the later (live) copy.
  #
  # The generated configuration.nix imports the SAME container profile the
  # image build uses (image/default.nix: virtualisation/docker-image.nix) so
  # `nixos-rebuild switch` evaluates the same module set as the image.
  # virtualisation/lxc-container.nix was considered and rejected: its
  # instance defaults (sshd on, empty root password, veth DHCP rules,
  # installBootLoader rewriting /sbin/init past the rootfs graft) fit an
  # LXC image, not Apple container-machine - access is `container machine
  # run`, root stays locked, and the runtime self-provisions the address.
  # This directory doubles as a flake root (flake.nix), so both paths above are
  # consumable by a flake-based configuration as `path:` inputs:
  #   inputs.cm.url = "path:/etc/nixos/machine-configuration.baked";  image-frozen
  #   inputs.cm.url = "path:/etc/nixos/machine-configuration";        live overlay
  # It must be a real directory: Nix copies a symlinked path input as the link
  # itself, and pure eval then refuses it - an environment.etc entry cannot
  # serve as the flake.
  environment.etc."nixos/configuration.nix".text = ''
    { modulesPath, ... }:
    {
      imports = [
        "''${modulesPath}/virtualisation/docker-image.nix"
      ]
      ++ (if builtins.pathExists /etc/nixos/machine-configuration
          then [ /etc/nixos/machine-configuration ]
          else [ /etc/nixos/machine-configuration.baked ]);
    }
  '';
}
