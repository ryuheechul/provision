# apple/tart

Provision macOS-only VMs with [tart](https://github.com/cirruslabs/tart) on
Apple Silicon. Each supported guest OS is a **flavor directory** under
`apple/tart/`:

- [`nixos/`](./nixos/) - NixOS inside a tart VM, installed from the channel ISO
  (manual install; `make run` boots the installer)
- [`macos/`](./macos/) - macOS inside a tart VM, cloned from a prebuilt vanilla
  Cirrus Labs image (no install step)

tart runs only on Apple Silicon macOS (Virtualization.framework), which is why
this lives under `apple/` alongside
[`container-machine`](../container-machine/).

## Tools

`tart` is declared in the repo's [`mise.toml`](../../mise.toml) - run
`mise install` there (see the root README), or put `tart` on `PATH` yourself.
Each flavor's `make run` stops with a hint if it cannot find `tart`.
