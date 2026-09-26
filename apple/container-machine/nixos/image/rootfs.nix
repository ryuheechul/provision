# Rootfs tree + bare rootfs tarball derivations for the container-machine image.
# Shell logic lives in bin/; this module only wires Nix inputs.
{ pkgs, system, nixosConfiguration, common }:

let
  # Unpack the NixOS system tarball and graft the bits a container-machine
  # needs that the tarball alone doesn't ship. No user is baked in here.
  rootfsTree = pkgs.runCommand "nixos-machine-rootfs" {
    nativeBuildInputs = [ pkgs.gnutar pkgs.xz ];
    NIXOS_SYSTEM_TARBALL = "${nixosConfiguration.config.system.build.tarball}/tarball/nixos-system-${system}.tar.xz";
    OS_RELEASE = "${common.osRelease}";
    BIN_SH = "${common.binSh}";
    BIN_SHIMS = common.binShimsEnv;
    SHELL_BOOTSTRAP = nixosConfiguration.config.system.build.containerMachineShellBootstrap;
    MACHINE_CONFIGURATION = ../machine-configuration;
  } (builtins.readFile ./bin/make-rootfs.sh);
in
{
  inherit rootfsTree;

  # bare-rootfs tarball, handy for `container build` (see buildContext)
  rootfs = pkgs.runCommand "nixos-machine-rootfs.tar.xz" {
    nativeBuildInputs = [ pkgs.gnutar pkgs.xz ];
    ROOTFS_TREE = "${rootfsTree}";
    TAR_FLAGS = common.tarFlags;
  } (builtins.readFile ./bin/pack-rootfs-tar.sh);
}
