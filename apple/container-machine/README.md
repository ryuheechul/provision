# Apple [Container machine](https://github.com/apple/container/blob/main/docs/container-machine.md)

Provision [Apple `container`](https://github.com/apple/container) [Container machines](https://github.com/apple/container/blob/main/docs/container-machine.md) with NixOS - generic and dotfiles-agnostic.

Each supported OS is a **flavor directory** under `apple/container-machine/`. The NixOS flavor is [`nixos/`](./nixos/), and its image build boots into a **switchable NixOS host**:

- [`nixos/`](./nixos/) - builds the OCI archive the machine boots. Initially `container`'s built-in provisioning supplies the login user + `/home` and boot services give that user a working `PATH` + `wheel`/`sudo`. The host is then `nixos-rebuild` switchable like OrbStack/`launchpad` (`user.nix` + `configuration.nix` via `bootstrap/foundation/nixos/switch.sh`). Build on a Linux box (`build.sh`) or inside an Apple `container` sandbox (`build-on-container.sh`) - no Lima VM needed. [`Makefile`](./nixos/Makefile) is the recommended entry point.

Flow: build the image, create the machine, shell in, then `nixos-rebuild switch` - done. See [`nixos/README.md`](./nixos/README.md) for the user model, compat shims, disk footprint, and clean-up.
