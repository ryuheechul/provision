# provision
Where I write code to provision (probably just) Virtual Machines that hopfully is useful.

Currently there is:

- [apple/container-machine/nixos](./apple/container-machine/nixos) - NixOS config for an Apple [Container machine](https://github.com/apple/container/blob/main/docs/container-machine.md)
- [apple/tart/nixos](./apple/tart/nixos) - NixOS inside a [tart](https://github.com/cirruslabs/tart) VM
- [lima](./lima) - Provision VMs with [Lima](https://github.com/lima-vm/lima)
  - [lima/dev](./lima/dev) - Dev VM on Lima's default template
  - [lima/nixos](./lima/nixos) - NixOS inside a Lima VM (reference for comparing against the [container machine](./apple/container-machine/nixos))
  - [lima/tailscale](./lima/tailscale) - Tailscale inside a Lima VM
  - [lima/screenshare](./lima/screenshare) - VNC VM working around `open vnc://` on macOS

## Tools

[mise.toml](./mise.toml) declares the tools these flows expect on `PATH` (`tart`, `lima`, `jq`, `container`, etc.).

- If you already have them, or will install them some other way, skip this section.
- If you have [mise](https://mise.jdx.dev) (or prefer provisioning with it):
  - `mise install` in the repo root installs whatever is missing
    - once per machine, and again after editing mise.toml
      - then activation gets them on `PATH`

- **Activated** - `eval "$(mise activate zsh)"` (or your shell) in the shell rc ([docs](https://mise.jdx.dev/getting-started.html#activate-mise)); entering the repo then puts the tools on `PATH` in every new shell. Nothing to do per shell.
- **Not activated** - not an expected setup, just a one-off stopgap: [`mise env`](https://mise.jdx.dev/cli/env.html#mise-env) loads the current shell once (`eval "$(mise env)"`).

The flows above never invoke `mise` themselves.
