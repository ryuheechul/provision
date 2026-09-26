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
  networking.hostName = lib.mkDefault "container-machine-nixos";

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
  #   /etc/nixos/machine-configuration        live overlay: written only by
  #     sync-config (make switch); present -> wins. rm -rf to remove it.
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
