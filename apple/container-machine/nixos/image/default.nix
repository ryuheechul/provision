# Builds a generic NixOS image (OCI archive) for Apple's `container`
# container-machine (https://github.com/apple/container/blob/main/docs/container-machine.md).
#
# Designed to be self-contained and dotfiles-agnostic.
#
# The image manages NO user declaratively at first: it boots as a stock NixOS
# container with root, and `container`'s built-in provisioning writes the macOS
# account into /etc/passwd on first boot. A `container-machine-shell-fix` boot
# service (see machine-configuration/) then points that user's shell at the
# /bin bootstrap (which waits for activation and hands off to the PATH
# wrapper); Apple supplies wheel/sudoers, and `container-machine-sudo-fix`
# installs the setuid sudo binary.
# The host is switchable (`nixos-rebuild switch` via channel + NIX_PATH +
# /etc/nixos/configuration.nix), like OrbStack/`launchpad`.
#
#   nix-build image -A image -o build/result      # on a Linux builder
#   container image load --input "$(realpath build/result)"   # on macOS
#   container machine create local/nixos-cm:latest --name nixos-cm
#
# Layout of this directory (everything that defines the image):
#   - common.nix  - shared platform facts, static file contents, OCI JSON
#                   templates (structure as Nix data),
#   - rootfs.nix  - unpacks the system tarball and grafts the
#                   container-machine boot bits (bin/make-rootfs.sh),
#   - oci.nix     - packs the rootfs into the minimal single-layer OCI
#                   archive (bin/pack-oci-image.sh) and the
#                   Dockerfile build context.
#   - bin/        - shellcheck-friendly shell bodies driven by Nix env vars.
# The guest system definition lives in ../machine-configuration/ (imported
# below; becomes /etc/nixos/machine-configuration/ at runtime).
#
# The build must run on a Linux machine (aarch64-linux for Apple Silicon);
# evaluation-only is platform-agnostic, so `nix-instantiate` works from macOS.

{ nixpkgs ? <nixpkgs>, system ? "aarch64-linux" }:

let
  nixosConfiguration = import "${nixpkgs}/nixos/lib/eval-config.nix" {
    inherit system;
    modules = [
      (import ../machine-configuration)
      # Tarball packaging lives in profiles/docker-container.nix (via this
      # import): system.build.tarball + container boot bits. docker-image itself
      # only adds Docker container markers (firewall off, /run/systemd/container).
      # Not for running Docker containers - Apple container-machine only needs
      # the tarball. https://github.com/NixOS/nixpkgs/blob/master/nixos/modules/virtualisation/docker-image.nix
      # The switch-time configuration.nix (machine-configuration/default.nix)
      # imports this same profile so nixos-rebuild switch does not flip
      # defaults; lxc-container.nix was rejected there - see that file.
      "${nixpkgs}/nixos/modules/virtualisation/docker-image.nix"
      {
        nixpkgs.hostPlatform = system;
        # Documentation is the image's heaviest passenger - the NixOS
        # manual output alone is 197 MB of store content (~0.47 GiB on
        # disk once unpacked) - and nothing consults it before the first
        # switch. This module only shapes the image eval: the switch-time
        # configuration never sees it (it evaluates machine-configuration
        # alone, where documentation.* keeps its NixOS default - enabled -
        # unless the host config says otherwise), so docs return with the
        # first switch. Dropping it shrinks the tarball and the set of
        # paths the GC-roots manifest has to pin for the machine's life.
        documentation.enable = false;
        documentation.man.enable = false;
        documentation.info.enable = false;
        documentation.doc.enable = false;
        documentation.nixos.enable = false;
      }
    ];
  };

  pkgs = nixosConfiguration.pkgs;

  imageName = "local/nixos-cm";
  imageTag = "latest";

  common = import ./common.nix {
    inherit pkgs system imageName imageTag;
  };

  rootfsBuild = import ./rootfs.nix {
    inherit pkgs system nixosConfiguration common;
  };

  ociBuild = import ./oci.nix {
    inherit pkgs common;
    inherit (rootfsBuild) rootfsTree rootfs;
  };
in
{
  inherit nixosConfiguration;
  inherit (rootfsBuild) rootfsTree rootfs;
  inherit (ociBuild) image buildContext;
}
