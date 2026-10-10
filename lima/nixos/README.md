# lima/nixos

NixOS as a [Lima](https://lima-vm.io) guest, via the
[nixos-lima](https://github.com/nixos-lima/nixos-lima) project and its
released image. Kept as a reference rather than something I actively use.

## Usage

    make start        # first call downloads the image (about 2 GB) and boots
    make enter        # shell into the guest
    make rebuild      # on the host: nixos-rebuild boot from a flake in the
                      # current directory, then restart the guest
    make teardown     # stop and delete the VM

`config.yaml` is vendored from nixos-lima's `nixos.yaml` template at v0.2.1.
The image URLs are sha512-digest-pinned, so the reference cannot drift with
upstream master.

## Customizing

To drive the guest from your own configuration, add nixos-lima as a flake
input and set `services.lima.enable = true`; see the
[config sample](https://github.com/nixos-lima/nixos-lima-config-sample).
The three rebuild flows are documented in the
[nixos-lima README](https://github.com/nixos-lima/nixos-lima#using-nixos-rebuild-to-customize-and-update-your-guest-instance).

Building your own base image on macOS needs a Linux builder
([linux-builder](https://nixos.org/manual/nixpkgs/unstable/#sec-darwin-builder)
or [nix-rosetta-builder](https://github.com/cpick/nix-rosetta-builder)).
Using the released image with in-guest `nixos-rebuild` does not.
