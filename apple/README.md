# apple

VM runtimes that only run on Apple Silicon macOS. Everything here uses
Virtualization.framework, so it needs a macOS host - unlike
[`lima`](../lima/), which also runs on Linux.

Each runtime is a directory with a flavor per guest OS:

- [`container-machine/`](./container-machine/) - Apple
  [Container machines](https://github.com/apple/container/blob/main/docs/container-machine.md),
  with a [`nixos/`](./container-machine/nixos/) flavor
- [`tart/`](./tart/) - [tart](https://github.com/cirruslabs/tart) VMs, with
  [`nixos/`](./tart/nixos/) and [`macos/`](./tart/macos/) flavors
